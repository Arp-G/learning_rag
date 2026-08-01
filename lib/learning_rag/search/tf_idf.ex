defmodule LearningRag.Search.TfIdf do
  @moduledoc """
  TF-IDF: the classic, simplest way to score how well a chunk matches a query.
  We keep it next to BM25 as a plain contrast — same index, same result shape,
  so the eval numbers differ only because the formula differs.

  The name is two ingredients multiplied together, one word at a time:

    TF — Term Frequency (counted inside ONE chunk): how many times the word
         appears in this chunk. More mentions → the chunk is more about it.

           tf = number of times the word appears in the chunk

    IDF — Inverse Document Frequency (counted ACROSS all chunks): how rare the
          word is in the whole collection. A word that's in only a few chunks
          is better at telling chunks apart than a word that's everywhere.

           idf = ln(N / df)     N = total chunks, df = chunks with the word

          e.g. with N = 100 chunks: a word in just 1 chunk → ln(100) ≈ 4.6
          (rare, valuable); a word in all 100 → ln(1) = 0 (useless, it's
          everywhere).

  For each query word that appears in the chunk, multiply the two and add them
  up:

      score = Σ  tf · idf  =  Σ  tf · ln(N / df)

  What TF-IDF is missing compared to BM25 (this is why BM25 scores better):

    * raw tf, no flattening — a word repeated 50 times counts 50×, so keyword
      stuffing wins. BM25's `k1` fixes this.
    * no length check — a long chunk piles up more tf and ranks higher just
      for being long. BM25's `b` fixes this.
    * ln(N/df) is exactly 0 when df = N — a word in every chunk adds nothing.

  It accepts (and ignores) `:k1` and `:b` so callers can treat it exactly like
  `Bm25.search/2`.
  """
  require Logger

  alias LearningRag.{Repo, Search}

  @default_top_k 10

  # Inputs: $1 = search words, $2 = how many results to return. Same shape as
  # the BM25 query on purpose — the only real difference is the contributions
  # block below.
  @sql """
  WITH query_terms AS (
    -- the search words, already stemmed the same way the chunks were
    SELECT unnest($1::text[]) AS term
  ),
  corpus AS (
    -- N = how many chunks exist. ::float8 so N / df below is real division,
    -- not integer (which would truncate, e.g. 3 / 2 = 1).
    SELECT count(*)::float8 AS n FROM chunks
  ),
  term_stats AS (
    -- for each search word, how many chunks contain it (df).
    SELECT p.term, count(*)::float8 AS df
    FROM postings p
    JOIN query_terms q ON q.term = p.term
    GROUP BY p.term
  ),
  contributions AS (
    -- Here we calculate for every (word, chunk):
    -- tf (count in this chunk) times
    -- idf (rarity = ln(N/df))
    -- and finally tf * idf
    SELECT
      p.chunk_id,
      p.term,
      p.tf,                                       -- number of times the word appears in the chunk
      ln(corpus.n / ts.df) AS idf,                -- ln(total chunks / chunks with the word )
      p.tf * ln(corpus.n / ts.df) AS contribution -- tf * idf
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
