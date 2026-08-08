defmodule LearningRag.Search.SemanticSearchTest do
  @moduledoc """
  Correctness of the cosine ranking, with NO network calls: we insert chunks
  with hand-built 1536-dim vectors and pass the query's vector directly via
  `:query_embedding`, so `Semantic.search` never embeds anything.

  The vectors are one-hot unit vectors — `unit(i)` points along axis i. Two
  one-hot vectors are identical when their axes match (cosine similarity 1) and
  orthogonal otherwise (similarity 0), which makes the expected ranking obvious.
  """
  use LearningRag.DataCase, async: true

  alias LearningRag.Repo
  alias LearningRag.Corpus.{Document, Chunk}
  alias LearningRag.Search.Semantic

  # A 1536-dim unit vector pointing along axis `i` (must be exactly 1536 long to
  # match the vector(1536) column).
  defp unit(i), do: List.duplicate(0.0, 1536) |> List.replace_at(i, 1.0) |> Pgvector.new()

  setup do
    doc = Repo.insert!(%Document{source: "test", external_id: "d1", title: "t", body: "b"})

    aligned =
      Repo.insert!(%Chunk{
        document_id: doc.id,
        chunk_index: 0,
        text: "aligned",
        token_count: 1,
        embedding: unit(0)
      })

    _orthogonal =
      Repo.insert!(%Chunk{
        document_id: doc.id,
        chunk_index: 1,
        text: "orthogonal",
        token_count: 1,
        embedding: unit(5)
      })

    # No embedding — must be excluded from results entirely.
    _unembedded =
      Repo.insert!(%Chunk{
        document_id: doc.id,
        chunk_index: 2,
        text: "unembedded",
        token_count: 1,
        embedding: nil
      })

    {:ok, doc: doc, aligned: aligned}
  end

  test "ranks the aligned chunk first and excludes un-embedded chunks", %{aligned: aligned} do
    results = Semantic.search("ignored", query_embedding: unit(0), top_k: 10)

    # Only the two embedded chunks are candidates; the NULL-embedding one is gone.
    assert length(results) == 2

    top = hd(results)
    assert top.chunk_id == aligned.id
    # Identical unit vectors → cosine similarity 1.0.
    assert_in_delta top.score, 1.0, 1.0e-6
    # The orthogonal chunk scores ~0 and ranks below.
    assert List.last(results).score < top.score
    # Semantic search has no per-term breakdown.
    assert top.breakdown == []
  end

  test "accepts a plain list as the query embedding too" do
    results =
      Semantic.search("ignored",
        query_embedding: List.duplicate(0.0, 1536) |> List.replace_at(0, 1.0)
      )

    assert_in_delta hd(results).score, 1.0, 1.0e-6
  end

  test "returns [] when nothing is embedded" do
    Repo.update_all(Chunk, set: [embedding: nil])
    assert Semantic.search("ignored", query_embedding: unit(0)) == []
  end

  test "top_k limits the number of results", %{doc: _doc} do
    assert length(Semantic.search("ignored", query_embedding: unit(0), top_k: 1)) == 1
  end
end
