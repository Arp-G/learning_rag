defmodule LearningRag.Eval.Query do
  @moduledoc """
  One of SciFact's 300 test queries (a scientific claim to find evidence for).

  These are not user searches — they're the fixed question set the benchmark
  ships, so every evaluation run asks the same questions and metric numbers
  stay comparable across runs and against published baselines.
  """
  use Ecto.Schema

  schema "queries" do
    # SciFact's own query id — kept so runs can be traced back to the dataset.
    field :external_id, :string
    field :text, :string
    # The query's embedding, filled by `mix rag.embed`. Storing it here means
    # semantic evaluation reuses it and never re-calls OpenAI per run.
    # Same vector(1536) column rules as chunks — see LearningRag.Corpus.Chunk
    # for how the dimension is set in the migration and what changing it involves.
    field :embedding, Pgvector.Ecto.Vector

    has_many :qrels, LearningRag.Eval.Qrel
  end
end
