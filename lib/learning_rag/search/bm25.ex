defmodule LearningRag.Search.Bm25 do
  @moduledoc """
  BM25 gives each chunk a score for how well it matches the search query. We
  do the whole calculation in SQL so you can follow every step.

  The idea: for every word in the query that also appears in a chunk, we add a
  bit to that chunk's score. How big that bit is depends on 3 things:

    1. How rare the word is.
       A word that shows up in almost every chunk (like "study") barely tells
       us anything, so matching it is worth little. A rare word (like
       "diffusion") is a strong signal, so matching it is worth a lot.
       `df` = how many chunks contain the word; fewer chunks → higher score.

    2. How many times the word appears in the chunk, but with diminishing
       returns. A chunk that says "cat" 5 times is more about cats than one
       that says it once. But going from 1 to 2 matters much more than going
       from 20 to 21 — the reward flattens out. The `k1` knob sets how fast it
       flattens. Default 1.2.

    3. How long the chunk is. A long chunk repeats words just because it's
       long, not because it's more on-topic, so we shrink the score for chunks
       that are longer than average. The `b` knob sets how strong that shrink
       is: `b = 0` ignores length, `b = 1` applies the full discount.
       Default 0.75.

  A chunk's final score is just the sum of these per-word bits.

  Example — search "cat", say there are 100 chunks and "cat" is in 20 of them:

    * Chunk A says "cat" 3 times and is short.
    * Chunk B says "cat" 3 times and is very long.

  Both match "cat" the same number of times, but A scores higher because B's
  length gets discounted (thing 3).

  The exact formula, added up over each query word that appears in the chunk:

      score = Σ  idf · (tf · (k1 + 1)) / (tf + k1 · (1 − b + b · dl/avgdl))

      idf = ln(1 + (N − df + 0.5) / (df + 0.5))

  where N = total chunks, df = chunks containing the word, tf = times the word
  appears in this chunk, dl = this chunk's length, avgdl = average chunk
  length. (The "1 +" in idf just keeps the score from ever going negative, and
  matches the standard BM25 that published benchmarks use.)

  `k1` and `b` are passed in at query time, so you can change them and re-score
  instantly — no reindexing needed. That's why postings stores the raw `tf`.
  """
  require Logger

  alias LearningRag.{Repo, Search}

  # The two BM25 knobs at their usual textbook defaults (see the module doc for
  # the full intuition). Both can be overridden per search via opts.
  #
  # k1 — how fast repeated words stop helping. Higher = repeats keep adding a
  # lot; lower = they flatten out faster (k1 = 0 → a word's count doesn't matter
  # at all, only whether it appears).
  @default_k1 1.2

  # b — how hard to discount long chunks. b = 0 ignores length entirely;
  # b = 1 fully discounts chunks that are longer than average.
  @default_b 0.75

  # how many results to return when the caller doesn't say
  @default_top_k 10

  # The scoring query. Each step of the math is its own named block (a CTE), so
  # the SQL reads top-to-bottom like the explanation above.
  # Inputs: $1 = search words, $2 = k1, $3 = b, $4 = how many results to return.
  @sql """
  WITH query_terms AS (
    -- the search words, already stemmed the same way the chunks were
    SELECT unnest($1::text[]) AS term
  ),
  corpus AS (
    -- totals we need: n = how many chunks exist, avgdl = average chunk length.
    -- the ::float8 casts matter — without them Postgres does integer division
    -- and truncates (e.g. 3 / 2 = 1).
    SELECT count(*)::float8 AS n, avg(token_count)::float8 AS avgdl
    FROM chunks
  ),
  term_stats AS (
    -- for each search word, how many chunks contain it (df).
    -- rarer word (smaller df) → bigger idf below → counts for more.
    SELECT p.term, count(*)::float8 AS df
    FROM postings p
    JOIN query_terms q ON q.term = p.term
    GROUP BY p.term
  ),
  contributions AS (
    -- Here we calculate for every (word, chunk):
    -- idf     (how rare the word is: rare word → big number)
    -- tf_part (its count in this chunk, flattened by k1 and shrunk for long chunks by b)
    -- the pair's score is idf * tf_part, added up per chunk in `ranked` below.
    -- one row per (word, chunk) so we can also show the per-word breakdown.
    SELECT
      p.chunk_id,
      p.term,
      p.tf,                                                     -- times the word appears in this chunk

      ln(1 + (corpus.n - ts.df + 0.5) / (ts.df + 0.5)) AS idf,  -- rarity = ln(1 + (N-df+0.5)/(df+0.5))

                                                                -- tf_part = tf·(k1+1) / (tf + k1·(1 - b + b·dl/avgdl))
                                                                -- count, flattened (k1) + length-adjusted (b)
      (p.tf * ($2::float8 + 1)) / (p.tf + $2::float8 * (1 - $3::float8 + $3::float8 * c.token_count / corpus.avgdl)) AS tf_part

    FROM postings p
    JOIN term_stats ts ON ts.term = p.term
    JOIN chunks c ON c.id = p.chunk_id
    CROSS JOIN corpus
  ),
  ranked AS (
    -- add up each chunk's word-scores to get its total, then keep the top N.
    -- the chunk_id tiebreak keeps ties in a stable order (tests rely on it).
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
    -- the per-word breakdown for each result, biggest contributor first.
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
        # k1 / 1 and b / 1 turn whole numbers into floats, so the SQL always
        # gets floats even if the caller passed e.g. 1 instead of 1.0.
        result = Repo.query!(@sql, [terms, k1 / 1, b / 1, top_k])
        Search.to_results(result)
    end
  end
end
