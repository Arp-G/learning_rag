defmodule LearningRag.Corpus.Posting do
  @moduledoc """
  One row of the inverted index: "`term` appears in `chunk`, `tf` times".

  This table is the term×chunk grid from search theory, stored the practical
  way: only the cells that aren't zero. You can read it two ways —

    * all rows with the same chunk_id → that chunk's word counts
    * all rows with the same term     → every chunk containing that word
      (this second view is what "inverted index" means)

  Scoring a chunk for a query only looks at the words the query and chunk
  share, so a search only ever touches a few rows per word — that's why
  keyword search is fast.

  We store the raw `tf` (a plain count), not a finished score, on purpose:
  idf, k1 and b all get applied later at query time, which is what lets you
  tweak them without rebuilding the index.
  """
  use Ecto.Schema

  @primary_key false
  schema "postings" do
    field :term, :string, primary_key: true
    field :tf, :integer

    belongs_to :chunk, LearningRag.Corpus.Chunk, primary_key: true
  end
end
