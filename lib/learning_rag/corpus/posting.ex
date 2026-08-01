defmodule LearningRag.Corpus.Posting do
  @moduledoc """
  One row of the inverted index: "`term` appears in `chunk`, `tf` times".

  This table is the sparse term×chunk matrix from IR theory, stored the only
  sensible way — as its nonzero cells (coordinate / COO form). A chunk's
  sparse vector is "all rows with this chunk_id"; the inverted index is
  "all rows with this term". Same data, two groupings.

  The BM25/TF-IDF score of a chunk for a query is a sparse dot product over
  these rows: only terms present in BOTH the query and the chunk contribute,
  which is exactly why sparse retrieval is fast.

  Note we store the raw `tf`, not a precomputed weight: IDF, k1 and b are all
  applied at query time, which is what keeps those parameters tweakable
  without reindexing.
  """
  use Ecto.Schema

  @primary_key false
  schema "postings" do
    field :term, :string, primary_key: true
    field :tf, :integer

    belongs_to :chunk, LearningRag.Corpus.Chunk, primary_key: true
  end
end
