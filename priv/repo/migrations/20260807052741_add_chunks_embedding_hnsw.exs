defmodule LearningRag.Repo.Migrations.AddChunksEmbeddingHnsw do
  @moduledoc """
  An HNSW index on chunk embeddings — the approximate-nearest-neighbor index
  that makes vector search scale.

  Without it, a query scans and scores every chunk (exact, but O(n)). HNSW
  builds a navigable small-world graph so a search only visits a fraction of
  the vectors — much faster at millions of rows, at the cost of occasionally
  missing a true nearest neighbor (approximate). `mix rag.ann` measures that
  recall-vs-speed tradeoff.

  `vector_cosine_ops` MUST match the `<=>` (cosine) operator the semantic
  scorer uses. Build params `m` (16) and `ef_construction` (64) are pgvector's
  defaults — fine for our ~7.7k rows; larger values build a better graph more
  slowly.
  """
  use Ecto.Migration

  def change do
    execute(
      "CREATE INDEX chunks_embedding_hnsw_idx ON chunks USING hnsw (embedding vector_cosine_ops)",
      "DROP INDEX chunks_embedding_hnsw_idx"
    )
  end
end
