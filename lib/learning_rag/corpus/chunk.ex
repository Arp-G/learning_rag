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

    belongs_to :document, LearningRag.Corpus.Document
  end
end
