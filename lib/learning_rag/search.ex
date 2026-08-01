defmodule LearningRag.Search do
  @moduledoc """
  Shared helpers for the sparse-retrieval scorers (`Search.Bm25`, `Search.TfIdf`).

  Both scorers follow the same shape — turn the query into stemmed terms, then
  run one SQL statement that computes the score as a sparse dot product over
  the postings. The bits they share live here.
  """
  alias LearningRag.Repo

  @doc """
  Turns raw query text into the same stemmed terms the indexer stored.

  This calls the EXACT SAME `to_tsvector('english', …)` used when building the
  postings (see `Indexer` — the 'english' config must match). Running query
  and documents through one pipeline is what makes their terms line up:
  "imaging" in a document and "imaging" in a query both become "imag".

  `tsvector_to_array` returns the lexemes deduplicated and sorted
  alphabetically. Dedup means a word repeated in the query counts once — the
  standard BM25 convention of ignoring within-query term frequency. (So the
  per-term breakdown is alphabetical, not in query order.)

  Returns `[]` for a query that is all stopwords/punctuation — callers should
  short-circuit and skip the SQL entirely.
  """
  @spec stem_terms(String.t()) :: [String.t()]
  def stem_terms(query_text) do
    %{rows: [[terms]]} =
      Repo.query!("SELECT tsvector_to_array(to_tsvector('english', $1::text))", [query_text])

    terms
  end

  @doc """
  Turns a scorer's raw `Postgrex.Result` into a list of result maps, keyed by
  the query's column names.

  Both scorers SELECT the same top-level columns (only the `breakdown` JSON
  differs), so decoding by column name keeps this generic and order-independent.
  The column names are our own fixed SQL aliases — never user input — so
  `String.to_atom/1` is safe here (no risk of atom-table exhaustion).
  """
  @spec to_results(Postgrex.Result.t()) :: [map()]
  def to_results(%Postgrex.Result{columns: columns, rows: rows}) do
    keys = Enum.map(columns, &String.to_atom/1)
    Enum.map(rows, fn row -> Map.new(Enum.zip(keys, row)) end)
  end
end
