defmodule LearningRag.Search do
  @moduledoc """
  Shared helpers for the two keyword scorers (`Search.Bm25`, `Search.TfIdf`).

  Both work the same way: turn the query into stemmed words, then run one SQL
  statement that scores each chunk by adding up the words it shares with the
  query. The shared bits live here.
  """
  alias LearningRag.Repo

  @doc """
  Turns raw query text into the same stemmed words the indexer stored.

  It runs the query through the EXACT SAME `to_tsvector('english', …)` used to
  build the postings. That's the whole trick to matching: "imaging" in a
  document and "imaging" in a query both become "imag", so they line up.

  `tsvector_to_array` gives the words back de-duplicated and sorted
  alphabetically. De-duplicated means a word typed twice in the query still
  counts once. (Sorted means the per-word breakdown comes out alphabetical,
  not in the order you typed.)

  Returns `[]` for a query that is all stopwords/punctuation — the scorers
  check for this and skip the SQL entirely.
  """
  @spec stem_terms(String.t()) :: [String.t()]
  def stem_terms(query_text) do
    %{rows: [[terms]]} =
      Repo.query!("SELECT tsvector_to_array(to_tsvector('english', $1::text))", [query_text])

    terms
  end

  @doc """
  Turns a scorer's raw query result into a list of maps, keyed by column name.

  Both scorers return the same columns (only the `breakdown` JSON differs), so
  decoding by column name keeps this generic. The column names come from our
  own SQL, never from user input, so turning them into atoms is safe here.
  """
  @spec to_results(Postgrex.Result.t()) :: [map()]
  def to_results(%Postgrex.Result{columns: columns, rows: rows}) do
    keys = Enum.map(columns, &String.to_atom/1)
    Enum.map(rows, fn row -> Map.new(Enum.zip(keys, row)) end)
  end
end
