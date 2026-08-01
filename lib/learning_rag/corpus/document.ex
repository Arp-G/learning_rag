defmodule LearningRag.Corpus.Document do
  @moduledoc """
  An original document, stored as it came in (title + raw body).

  We never search this table directly — search runs over `Chunk`s. It's here so
  we can trace any search hit back to where it came from, and so we can re-chunk
  the corpus without downloading it again.
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
