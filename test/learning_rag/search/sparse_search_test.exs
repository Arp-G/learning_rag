defmodule LearningRag.Search.SparseSearchTest do
  @moduledoc """
  Correctness guard for both scorers: index a tiny hand-computable corpus
  through the REAL pipeline (Chunker → postings SQL → token_count SQL), then
  check the SQL scores against the BM25/TF-IDF formulas re-implemented in plain
  Elixir here. If the SQL drifts (an integer division, a misplaced paren, a
  wrong IDF), the two disagree and the test fails.

  Fixture words are lowercase, non-stopword, non-plural, hyphen/digit-free, so
  the stemmer leaves them alone and the term frequencies are obvious. That
  assumption is itself asserted (see the token_count test).
  """
  use LearningRag.DataCase, async: true

  alias LearningRag.Repo
  alias LearningRag.Corpus.{Document, Chunk}
  alias LearningRag.Ingest.{Chunker, Indexer}
  alias LearningRag.Search.{Bm25, TfIdf}

  # Three documents, each a single chunk (bodies are far under 200 words):
  #
  #   D1  "alpha" / "cat cat dog"          tokens {alpha:1, cat:2, dog:1}  dl=4
  #   D2  "beta"  / "cat fish fish fish"    tokens {beta:1, cat:1, fish:3}  dl=5
  #   D3  "gamma" / "dog dog bird"          tokens {gamma:1, dog:2, bird:1} dl=4
  #
  # So N = 3 chunks, avgdl = (4 + 5 + 4) / 3 = 13/3, and for the query
  # "cat dog": df(cat) = 2 (D1,D2), df(dog) = 2 (D1,D3).
  @docs [
    {"d1", "alpha", "cat cat dog"},
    {"d2", "beta", "cat fish fish fish"},
    {"d3", "gamma", "dog dog bird"}
  ]

  @n 3
  @avgdl 13 / 3

  setup do
    for {ext, title, body} <- @docs do
      doc = Repo.insert!(%Document{source: "test", external_id: ext, title: title, body: body})

      title
      |> Chunker.chunk(body)
      |> Enum.each(fn chunk ->
        Repo.insert!(%Chunk{
          document_id: doc.id,
          chunk_index: chunk.chunk_index,
          text: chunk.text,
          token_count: 0
        })
      end)
    end

    # Same SQL the indexer runs in production.
    Indexer.build_postings!()
    Indexer.backfill_token_counts!()
    :ok
  end

  # --- BM25/TF-IDF formulas, re-implemented independently of the SQL --------

  defp bm25(tf, df, dl, k1, b) do
    idf = :math.log(1 + (@n - df + 0.5) / (df + 0.5))
    tf_part = tf * (k1 + 1) / (tf + k1 * (1 - b + b * dl / @avgdl))
    idf * tf_part
  end

  defp tfidf(tf, df), do: tf * :math.log(@n / df)

  defp score_by_doc(results), do: Map.new(results, &{&1.doc_external_id, &1.score})

  # --- tests ---------------------------------------------------------------

  test "token counts match the expected stop-worded lengths" do
    # If the stemmer did something surprising to a fixture word, these would be
    # wrong — so this pins down the assumption the hand arithmetic relies on.
    counts =
      Repo.all(Chunk)
      |> Repo.preload(:document)
      |> Map.new(&{&1.document.external_id, &1.token_count})

    assert counts == %{"d1" => 4, "d2" => 5, "d3" => 4}
  end

  test "BM25 scores and ordering match the formula" do
    k1 = 1.2
    b = 0.75
    results = Bm25.search("cat dog", k1: k1, b: b, top_k: 10)

    # D1 matches cat(tf=2) + dog(tf=1); D2 matches cat(tf=1); D3 matches dog(tf=2).
    expected = %{
      "d1" => bm25(2, 2, 4, k1, b) + bm25(1, 2, 4, k1, b),
      "d2" => bm25(1, 2, 5, k1, b),
      "d3" => bm25(2, 2, 4, k1, b)
    }

    actual = score_by_doc(results)

    for {doc, score} <- expected do
      assert_in_delta actual[doc], score, 1.0e-9
    end

    # D1 (two matching terms) beats D3 (one dense match) beats D2 (one match
    # in a longer chunk, so length-normalized down).
    assert Enum.map(results, & &1.doc_external_id) == ["d1", "d3", "d2"]
  end

  test "the k1 knob changes saturation (k1=0 makes tf irrelevant)" do
    # With k1 = 0 the tf term collapses to tf*1/(tf) = 1, so every match
    # contributes exactly its IDF regardless of tf. dog(tf=2) in D3 then ties
    # cat(tf=1) in D2 on the tf part — the score becomes pure IDF.
    results = Bm25.search("cat dog", k1: 0.0, b: 0.75, top_k: 10)
    scores = score_by_doc(results)

    idf = :math.log(1 + (@n - 2 + 0.5) / (2 + 0.5))
    assert_in_delta scores["d2"], idf, 1.0e-9
    assert_in_delta scores["d3"], idf, 1.0e-9
    assert_in_delta scores["d1"], 2 * idf, 1.0e-9
  end

  test "TF-IDF scores and ordering match the formula" do
    results = TfIdf.search("cat dog", top_k: 10)

    expected = %{
      "d1" => tfidf(2, 2) + tfidf(1, 2),
      "d2" => tfidf(1, 2),
      "d3" => tfidf(2, 2)
    }

    actual = score_by_doc(results)

    for {doc, score} <- expected do
      assert_in_delta actual[doc], score, 1.0e-9
    end

    # No length normalization, no saturation — raw tf drives everything.
    assert Enum.map(results, & &1.doc_external_id) == ["d1", "d3", "d2"]
  end

  test "each result's breakdown contributions sum to its score" do
    for result <- Bm25.search("cat dog fish", top_k: 10) do
      sum = result.breakdown |> Enum.map(& &1["contribution"]) |> Enum.sum()
      assert_in_delta sum, result.score, 1.0e-9
    end
  end

  test "an all-stopword query returns no results without touching the scorer SQL" do
    assert Bm25.search("the of and", top_k: 10) == []
    assert TfIdf.search("the of and", top_k: 10) == []
  end

  test "top_k limits the number of results" do
    assert length(Bm25.search("cat dog fish bird", top_k: 1)) == 1
  end
end
