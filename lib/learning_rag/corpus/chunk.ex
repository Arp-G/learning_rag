defmodule LearningRag.Corpus.Chunk do
  @moduledoc """
  The retrieval unit: one passage cut from a document by the chunker.

  `token_count` is the chunk's stop-worded length — the sum of `tf` over its
  postings, i.e. how many index-relevant words it contains. That number is
  `|D|` in the BM25 formula, where it drives the length-normalization term
  `dl / avgdl` (longer chunks get their term matches discounted).
  """
  use Ecto.Schema

  schema "chunks" do
    field :chunk_index, :integer
    field :text, :string
    field :token_count, :integer

    belongs_to :document, LearningRag.Corpus.Document
  end
end
