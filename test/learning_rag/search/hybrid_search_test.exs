defmodule LearningRag.Search.HybridSearchTest do
  @moduledoc """
  End-to-end hybrid search over a tiny corpus (no network): real BM25 postings
  plus hand-built embeddings, then fuse. The fixture is rigged so BM25 and
  semantic DISAGREE on the top result, which lets us see fusion actually choosing.

    chunk A "cat cat cat" / embedding axis 5  → BM25 loves it (tf=3), semantic ignores it
    chunk B "dog"         / embedding axis 0  → BM25 misses it, semantic loves it (query is axis 0)
    chunk C "cat"         / embedding axis 1  → BM25 minor hit (tf=1), semantic ignores it

  Query text "cat", query embedding = axis 0. So BM25's pick is A, semantic's is B.
  """
  use LearningRag.DataCase, async: true

  alias LearningRag.Repo
  alias LearningRag.Corpus.{Document, Chunk}
  alias LearningRag.Ingest.Indexer
  alias LearningRag.Search.Hybrid

  defp unit(i), do: List.duplicate(0.0, 1536) |> List.replace_at(i, 1.0) |> Pgvector.new()

  setup do
    for {ext, text, axis} <- [{"A", "cat cat cat", 5}, {"B", "dog", 0}, {"C", "cat", 1}] do
      doc = Repo.insert!(%Document{source: "test", external_id: ext, title: ext, body: text})

      # Insert the chunk text directly (no chunker) so the title isn't mixed in
      # and the term frequencies are exactly as written.
      Repo.insert!(%Chunk{
        document_id: doc.id,
        chunk_index: 0,
        text: text,
        token_count: 0,
        embedding: unit(axis)
      })
    end

    Indexer.build_postings!()
    Indexer.backfill_token_counts!()
    :ok
  end

  defp docs(results), do: Enum.map(results, & &1.doc_external_id)

  test "RRF favors the chunk both scorers rank, and rewards being in both lists" do
    # BM25 order: [A, C]; semantic order: [B, A, C].
    #   A: in both  -> 1/61 + 1/62 ≈ 0.0325  (highest)
    #   C: in both  -> 1/62 + 1/63 ≈ 0.0320
    #   B: sem only -> 1/61        ≈ 0.0164
    # So A tops, and C (in both, low ranks) still beats B (in one, top rank).
    results = Hybrid.search("cat", query_embedding: unit(0), method: "rrf", k: 60, top_k: 10)

    assert docs(results) == ["A", "C", "B"]
  end

  test "weighted beta slides between BM25's pick and semantic's pick" do
    # beta = 0 → pure BM25 → A on top; beta = 1 → pure semantic → B on top.
    bm25_side =
      Hybrid.search("cat", query_embedding: unit(0), method: "weighted", beta: 0.0, top_k: 10)

    sem_side =
      Hybrid.search("cat", query_embedding: unit(0), method: "weighted", beta: 1.0, top_k: 10)

    assert hd(docs(bm25_side)) == "A"
    assert hd(docs(sem_side)) == "B"
  end

  test "results carry the standard keys and a per-scorer breakdown" do
    [top | _] = Hybrid.search("cat", query_embedding: unit(0), top_k: 10)

    # Same shape as the other scorers.
    for key <- [:chunk_id, :score, :chunk_index, :text, :document_id, :doc_external_id, :title] do
      assert Map.has_key?(top, key)
    end

    # A is found by both scorers, so its breakdown lists both sources.
    assert top.doc_external_id == "A"
    sources = Enum.map(top.breakdown, & &1["source"]) |> Enum.sort()
    assert sources == ["bm25", "semantic"]

    # B is found only by semantic, so its breakdown has just that source.
    b =
      Enum.find(
        Hybrid.search("cat", query_embedding: unit(0), top_k: 10),
        &(&1.doc_external_id == "B")
      )

    assert Enum.map(b.breakdown, & &1["source"]) == ["semantic"]
  end

  test "top_k limits the number of fused results" do
    assert length(Hybrid.search("cat", query_embedding: unit(0), top_k: 1)) == 1
  end
end
