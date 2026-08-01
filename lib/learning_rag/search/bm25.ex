defmodule LearningRag.Search.Bm25 do
  @moduledoc """
  BM25 ranking, computed entirely in SQL so every part of the formula stays
  visible and inspectable.

  For a query Q and chunk D, BM25 sums one contribution per shared term t:

      score(D, Q) = Σ  IDF(t) · (tf · (k1 + 1)) / (tf + k1 · (1 − b + b · |D|/avgdl))
                   t∈Q

      IDF(t) = ln(1 + (N − df + 0.5) / (df + 0.5))    ("Lucene" variant)

  with N = number of chunks, df = chunks containing t, tf = t's frequency in
  D, |D| = D's token_count, avgdl = mean token_count. This is a sparse dot
  product: only terms present in both Q and D contribute.

  What BM25 adds over plain TF-IDF is exactly the two knobs:

    * `k1` — term-frequency saturation. A term's tf contribution rises toward
      a ceiling of (k1 + 1) instead of growing linearly, so the 20th mention
      of a word barely beats the 5th. Typical: 1.2.
    * `b`  — length normalization strength. `b = 1` fully penalizes chunks
      longer than average (their matches are "diluted"); `b = 0` ignores
      length entirely. Typical: 0.75.

  Both are query-time bind parameters, so changing them re-scores instantly —
  no reindexing. That's the whole reason we store raw `tf` in the postings.

  We use the Lucene IDF variant (the `1 +` inside the log) rather than the
  classic Robertson IDF because it can't go negative, and because it's what
  the published BM25 baselines we compare against use.
  """
  require Logger

  alias LearningRag.{Repo, Search}

  # Standard BM25 defaults.
  @default_k1 1.2
  @default_b 0.75
  @default_top_k 10

  # The scoring query. One named CTE per concept in the formula above, so the
  # SQL reads like the math. Params: $1 = terms (text[]), $2 = k1, $3 = b,
  # $4 = top_k. (Defined before search/2 — module attributes read as nil if
  # referenced before their definition.)
  @sql """
  WITH query_terms AS (
    -- The stemmed query lexemes, produced in Elixir by the SAME
    -- to_tsvector('english', …) used at indexing time.
    SELECT unnest($1::text[]) AS term
  ),
  corpus AS (
    -- Live corpus statistics. The ::float8 casts are load-bearing: count(*)
    -- is bigint, and bigint / bigint would truncate to an integer.
    SELECT count(*)::float8 AS n, avg(token_count)::float8 AS avgdl
    FROM chunks
  ),
  term_stats AS (
    -- df(t): how many chunks contain each query term. Rarer term → smaller
    -- df → larger IDF: rare words are the informative ones.
    SELECT p.term, count(*)::float8 AS df
    FROM postings p
    JOIN query_terms q ON q.term = p.term
    GROUP BY p.term
  ),
  contributions AS (
    -- One row per (query term × matching chunk): that term's additive share
    -- of the chunk's score. Kept as rows so we can show a per-term breakdown.
    SELECT
      p.chunk_id,
      p.term,
      p.tf,
      -- IDF(t): ln(1 + (N − df + 0.5)/(df + 0.5)).
      ln(1 + (corpus.n - ts.df + 0.5) / (ts.df + 0.5)) AS idf,
      -- Saturating TF with length normalization:
      --   tf·(k1+1) / (tf + k1·(1 − b + b·|D|/avgdl))
      (p.tf * ($2::float8 + 1))
        / (p.tf + $2::float8 * (1 - $3::float8 + $3::float8 * c.token_count / corpus.avgdl))
        AS tf_part
    FROM postings p
    JOIN term_stats ts ON ts.term = p.term
    JOIN chunks c ON c.id = p.chunk_id
    CROSS JOIN corpus
  ),
  ranked AS (
    -- score(D,Q) = Σ idf · tf_part. The chunk_id tiebreak makes ties
    -- deterministic (the tests depend on a stable order).
    SELECT chunk_id, sum(idf * tf_part) AS score
    FROM contributions
    GROUP BY chunk_id
    ORDER BY score DESC, chunk_id
    LIMIT $4
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
    -- Per-term breakdown for the survivors, biggest contribution first.
    jsonb_agg(
      jsonb_build_object(
        'term', co.term, 'tf', co.tf, 'idf', co.idf,
        'tf_part', co.tf_part, 'contribution', co.idf * co.tf_part
      ) ORDER BY co.idf * co.tf_part DESC
    ) AS breakdown
  FROM ranked r
  JOIN contributions co ON co.chunk_id = r.chunk_id
  JOIN chunks ch ON ch.id = r.chunk_id
  JOIN documents d ON d.id = ch.document_id
  GROUP BY r.chunk_id, r.score, ch.id, d.id
  ORDER BY r.score DESC, r.chunk_id
  """

  @doc """
  Ranks chunks against `query_text` by BM25.

  Options: `:k1`, `:b`, `:top_k` (all default to the standard values above).
  Returns a list of result maps ordered best-first, each with `:score`, the
  chunk/document fields, and a `:breakdown` list showing how each query term
  contributed. Returns `[]` for a query with no searchable terms.
  """
  def search(query_text, opts \\ []) do
    k1 = Keyword.get(opts, :k1, @default_k1)
    b = Keyword.get(opts, :b, @default_b)
    top_k = Keyword.get(opts, :top_k, @default_top_k)

    case Search.stem_terms(query_text) do
      [] ->
        Logger.info("BM25: #{inspect(query_text)} has no searchable terms → []")
        []

      terms ->
        Logger.info("BM25: #{inspect(query_text)} → #{inspect(terms)} (k1=#{k1}, b=#{b})")
        # k1 / 1 and b / 1 force floats even if the caller passed integers,
        # so the ::float8 params always receive floats.
        result = Repo.query!(@sql, [terms, k1 / 1, b / 1, top_k])
        Search.to_results(result)
    end
  end
end
