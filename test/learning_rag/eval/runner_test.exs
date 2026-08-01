defmodule LearningRag.Eval.RunnerTest do
  @moduledoc """
  Checks the eval runner's two responsibilities that aren't the metrics
  themselves: mapping chunk hits to parent documents (dedup, best chunk wins)
  and averaging per-query metrics into the summary.
  """
  use LearningRag.DataCase, async: true

  alias LearningRag.Repo
  alias LearningRag.Corpus.{Document, Chunk}
  alias LearningRag.Eval.{Query, Qrel, Runner}
  alias LearningRag.Ingest.{Chunker, Indexer}

  # A "scorer" that just replays a fixed chunk ranking, so the test controls
  # exactly what the runner sees — no dependency on BM25/TF-IDF here.
  defmodule StubScorer do
    def search(query_text, _opts) do
      Process.get({:results, query_text}, [])
    end
  end

  setup do
    docs =
      for {ext, title, body} <- [
            {"d1", "alpha", "cat dog"},
            {"d2", "beta", "cat fish"},
            {"d3", "gamma", "bird"}
          ],
          into: %{} do
        doc = Repo.insert!(%Document{source: "test", external_id: ext, title: title, body: body})

        title
        |> Chunker.chunk(body)
        |> Enum.each(fn c ->
          Repo.insert!(%Chunk{
            document_id: doc.id,
            chunk_index: c.chunk_index,
            text: c.text,
            token_count: 0
          })
        end)

        {ext, doc}
      end

    Indexer.build_postings!()
    Indexer.backfill_token_counts!()

    {:ok, docs: docs}
  end

  test "maps chunk hits to parent documents, keeping the best-ranked chunk", %{docs: docs} do
    query = Repo.insert!(%Query{external_id: "q1", text: "q1"})
    # d1 is the single relevant document for this query.
    Repo.insert!(%Qrel{query_id: query.id, document_id: docs["d1"].id, relevance: 1})

    # The scorer returns two chunks of d2 (ranks 1–2), then d1 (rank 3).
    # After collapsing to documents the ranking is [d2, d1], so the relevant
    # d1 sits at document-rank 2 → reciprocal rank 1/2.
    Process.put({:results, "q1"}, [
      %{document_id: docs["d2"].id, score: 3.0},
      %{document_id: docs["d2"].id, score: 2.0},
      %{document_id: docs["d1"].id, score: 1.0}
    ])

    %{mean: mean, query_count: 1} = Runner.run(StubScorer)

    assert_in_delta mean.mrr_at_10, 0.5, 1.0e-9
    assert_in_delta mean.r_at_10, 1.0, 1.0e-9
  end

  test "averages metrics across queries", %{docs: docs} do
    q1 = Repo.insert!(%Query{external_id: "q1", text: "q1"})
    q2 = Repo.insert!(%Query{external_id: "q2", text: "q2"})
    Repo.insert!(%Qrel{query_id: q1.id, document_id: docs["d1"].id, relevance: 1})
    Repo.insert!(%Qrel{query_id: q2.id, document_id: docs["d1"].id, relevance: 1})

    # q1: relevant doc at rank 1 (RR = 1). q2: relevant doc at rank 2 (RR = 1/2).
    Process.put({:results, "q1"}, [%{document_id: docs["d1"].id, score: 1.0}])

    Process.put({:results, "q2"}, [
      %{document_id: docs["d2"].id, score: 2.0},
      %{document_id: docs["d1"].id, score: 1.0}
    ])

    %{mean: mean, query_count: 2} = Runner.run(StubScorer)

    # Mean reciprocal rank = (1 + 0.5) / 2 = 0.75.
    assert_in_delta mean.mrr_at_10, 0.75, 1.0e-9
  end
end
