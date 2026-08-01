defmodule LearningRag.Search.TfIdf do
  @moduledoc """
  Classic TF-IDF ranking — deliberately the simplest textbook variant, kept
  as a side-by-side contrast with `Search.Bm25`.

      score(D, Q) = Σ  tf · ln(N / df)
                   t∈Q

  with tf = term frequency in the chunk, N = number of chunks, df = chunks
  containing the term. Compared to BM25, notice what's *missing*:

    * raw tf, no saturation — a term repeated 50× counts 50×, so keyword
      stuffing wins (BM25's k1 fixes this).
    * no length normalization — a longer chunk racks up more tf and ranks
      higher just for being long (BM25's b fixes this).
    * ln(N/df) is exactly 0 when df = N — a term appearing in EVERY chunk
      carries no information and contributes nothing. (BM25's `1 +` variant
      keeps such a term slightly positive instead.)

  Same inverted index, same query pipeline, same result shape as BM25 — so the
  eval runner can swap one for the other and the difference in the metrics is
  purely the difference in these two formulas. It accepts (and ignores) `:k1`
  and `:b` so callers can treat both scorers identically.
  """
  require Logger

  alias LearningRag.{Repo, Search}

  @default_top_k 10

  # Params: $1 = terms (text[]), $2 = top_k. Same CTE skeleton as BM25 so the
  # two are easy to diff — the whole difference is in the `contributions` CTE.
  @sql """
  WITH query_terms AS (
    SELECT unnest($1::text[]) AS term
  ),
  corpus AS (
    -- ::float8 so N / df below is real division, not integer truncation.
    SELECT count(*)::float8 AS n FROM chunks
  ),
  term_stats AS (
    SELECT p.term, count(*)::float8 AS df
    FROM postings p
    JOIN query_terms q ON q.term = p.term
    GROUP BY p.term
  ),
  contributions AS (
    -- The entire TF-IDF model: tf · ln(N/df). No saturation, no length term.
    SELECT
      p.chunk_id,
      p.term,
      p.tf,
      ln(corpus.n / ts.df) AS idf,
      p.tf * ln(corpus.n / ts.df) AS contribution
    FROM postings p
    JOIN term_stats ts ON ts.term = p.term
    CROSS JOIN corpus
  ),
  ranked AS (
    SELECT chunk_id, sum(contribution) AS score
    FROM contributions
    GROUP BY chunk_id
    ORDER BY score DESC, chunk_id
    LIMIT $2
  )
  SELECT
    r.chunk_id,
    r.score,
    ch.chunk_index,
    ch.text,
    ch.token_count,
    d.id AS document_id,
    d.external_id AS doc_external_id,
    d.title,
    jsonb_agg(
      jsonb_build_object(
        'term', co.term, 'tf', co.tf, 'idf', co.idf, 'contribution', co.contribution
      ) ORDER BY co.contribution DESC
    ) AS breakdown
  FROM ranked r
  JOIN contributions co ON co.chunk_id = r.chunk_id
  JOIN chunks ch ON ch.id = r.chunk_id
  JOIN documents d ON d.id = ch.document_id
  GROUP BY r.chunk_id, r.score, ch.id, d.id
  ORDER BY r.score DESC, r.chunk_id
  """

  @doc """
  Ranks chunks against `query_text` by classic TF-IDF.

  Options: `:top_k` (default #{@default_top_k}). Accepts and ignores `:k1`/`:b`
  so it's drop-in interchangeable with `Search.Bm25.search/2`.
  """
  def search(query_text, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, @default_top_k)

    case Search.stem_terms(query_text) do
      [] ->
        Logger.info("TF-IDF: #{inspect(query_text)} has no searchable terms → []")
        []

      terms ->
        Logger.info("TF-IDF: #{inspect(query_text)} → #{inspect(terms)}")
        result = Repo.query!(@sql, [terms, top_k])
        Search.to_results(result)
    end
  end
end
