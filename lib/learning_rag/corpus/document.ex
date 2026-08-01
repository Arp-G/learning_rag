defmodule LearningRag.Corpus.Document do
  @moduledoc """
  An original ingested document, stored as it arrived (title + raw body).

  Documents are never searched directly — retrieval happens over `Chunk`s.
  This table exists for provenance (mapping any search hit back to its
  source) and so the corpus can be re-chunked without re-downloading.
  """
  use Ecto.Schema

  schema "documents" do
    # "scifact" for the benchmark corpus; other sources (e.g. uploads) later.
    field :source, :string
    # The dataset's own id (BEIR `_id`). Qrels reference documents by this.
    field :external_id, :string
    field :title, :string
    field :body, :string

    has_many :chunks, LearningRag.Corpus.Chunk

    timestamps(type: :utc_datetime)
  end
end
