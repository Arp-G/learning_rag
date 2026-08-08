defmodule LearningRag.Repo.Migrations.AddEmbeddings do
  @moduledoc """
  Phase 2: dense embeddings. Enables the pgvector extension and adds a
  1536-dim `vector` column (OpenAI text-embedding-3-small's size) to the chunks
  we search over and to the eval queries.

  The columns are NULLable — `mix rag.embed` fills them in a separate step, and
  the semantic scorer simply skips rows whose embedding is still NULL.
  """
  use Ecto.Migration

  def change do
    # Turn on pgvector. IF NOT EXISTS makes it a no-op when it's already on
    # (the `mix test` alias re-runs migrations on the test DB).
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")

    # `size: 1536` renders `vector(1536)` — the dimensionality of
    # text-embedding-3-small. The query and the chunks must share it.
    alter table(:chunks) do
      add :embedding, :vector, size: 1536
    end

    alter table(:queries) do
      add :embedding, :vector, size: 1536
    end
  end
end
