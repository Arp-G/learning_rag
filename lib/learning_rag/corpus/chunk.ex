defmodule LearningRag.Corpus.Chunk do
  @moduledoc """
  The retrieval unit: one passage cut from a document by the chunker.

  `token_count` is how many words the chunk has after stopwords are dropped
  (the sum of `tf` over its postings). BM25 uses this as the chunk's length:
  longer chunks get their matches discounted — the `dl / avgdl` part of the
  formula.
  """
  use Ecto.Schema

  schema "chunks" do
    field :chunk_index, :integer
    field :text, :string
    field :token_count, :integer
    # Dense embedding of this chunk (OpenAI text-embedding-3-small, 1536-dim).
    # NULL until `mix rag.embed` runs; semantic search skips NULLs.
    #
    # `Pgvector.Ecto.Vector` is only the Elixir <-> Postgres translator and is
    # dimension-agnostic — the actual size lives in the COLUMN, not on this line.
    # The migration defines it (`add :embedding, :vector, size: 1536` → the
    # column type `vector(1536)`) and Postgres enforces it: a vector of the wrong
    # length is rejected on insert ("expected 1536 dimensions, not N").
    #
    # So the number is tied to the embedding model, and a few things follow:
    #   * The column size MUST equal the model's output dimensions, and must
    #     match `@model` in `LearningRag.Embed.OpenAI` — if they drift, inserts
    #     fail with that dimension error.
    #   * Switching models (say a 384-dim local model, or 3072-dim
    #     text-embedding-3-large) needs a NEW migration to change the column size
    #     AND re-embedding everything (existing vectors are the wrong length).
    #     This `field` line itself does not change.
    #   * The HNSW index caps at 2000 dimensions. 1536 is fine. A bigger model
    #     (e.g. text-embedding-3-large at 3072) can't be HNSW-indexed as a plain
    #     `vector` — two standard fixes, both of which you'd often want anyway for
    #     memory/latency, not just to dodge the cap:
    #       - `halfvec`: store and index as half-precision (2-byte) vectors, which
    #         HNSW supports up to 4000 dims. Costs a little precision, roughly
    #         halves storage, and usually barely dents recall.
    #       - Matryoshka: text-embedding-3-* are trained so you can ask the API
    #         for fewer dimensions (the `dimensions` param, e.g. 1024) and lose
    #         very little quality — which also shrinks storage and speeds search.
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :document, LearningRag.Corpus.Document
  end
end
