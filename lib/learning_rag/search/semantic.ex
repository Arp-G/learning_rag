defmodule LearningRag.Search.Semantic do
  @moduledoc """
  Dense (semantic) search: rank chunks by how close their embedding is to the
  query's embedding, using cosine similarity.

  Unlike BM25/TF-IDF, which match on shared words, this matches on *meaning*:
  the query and a chunk can score high with no words in common, because the
  embedding model maps text with similar meaning to nearby vectors. That's the
  whole point — it catches paraphrases and synonyms that keyword search misses.

  The comparison is a cosine between 1536-dim vectors. pgvector's `<=>` returns
  cosine DISTANCE, where SMALLER means closer: 0 = identical direction,
  1 = unrelated, 2 = opposite. That's "lower is better", the opposite of how
  BM25 scores read, so we flip it into a similarity SCORE with `1 - distance`:

      distance 0 (identical)  ->  score  1   (best)
      distance 1 (unrelated)  ->  score  0
      distance 2 (opposite)   ->  score -1   (worst)

  Now higher = better, matching the sparse scorers. (Note these are two scales
  for the same thing: "distance near 1" is a bad match, but a "score near 1" is
  a great one. Ranking by ascending distance or by descending score gives the
  identical order — the flip is only so the number reads like BM25's.) In
  practice real embeddings rarely reach "opposite"; related text sits in a
  narrowish positive band, so scores usually land around 0.3–0.8.

  Only chunks that have been embedded (see `mix rag.embed`) can match.

  ## Exact vs approximate (HNSW)

  By default this runs whatever plan Postgres picks: a full scan (exact nearest
  neighbors) until an HNSW index exists, then the index (approximate, much
  faster at scale). Two opts let callers pin the behavior — used by `mix rag.ann`
  to compare the two:

    * `exact: true`   — force the exact full scan (disable the index)
    * `ef_search: n`  — use the HNSW index with this search effort (higher n =
      more accurate + slower)
  """
  require Logger

  alias LearningRag.{Repo, Search, Embed}

  @default_top_k 10

  # $1 = query vector, $2 = top_k. `nearest` finds the closest chunks by cosine
  # distance; the outer query attaches the chunk/document fields and reports
  # similarity as the score. `WHERE embedding IS NOT NULL` skips un-embedded
  # rows so an un-embedded corpus simply returns nothing.
  @sql """
  WITH nearest AS (
    SELECT id AS chunk_id,
           1 - (embedding <=> $1) AS score   -- `<=>` pg operator gives cosine distance NOT cosine similarity
                                             -- cosine similarity = 1 - cosine_distance (higher = better = more similar)
    FROM chunks
    WHERE embedding IS NOT NULL
    ORDER BY embedding <=> $1                -- cosine distance ascending = nearest first
    LIMIT $2
  )
  SELECT n.chunk_id, n.score, ch.chunk_index, ch.text, ch.token_count,
         d.id AS document_id, d.external_id AS doc_external_id, d.title,
         '[]'::jsonb AS breakdown             -- no per-word breakdown for vector search
  FROM nearest n
  JOIN chunks ch   ON ch.id = n.chunk_id
  JOIN documents d ON d.id = ch.document_id
  ORDER BY n.score DESC, n.chunk_id
  """

  @doc """
  Ranks chunks against `query_text` by cosine similarity.

  Options: `:top_k` (default #{@default_top_k}); `:query_embedding` (a stored
  vector to skip the live embed call — the eval path uses this); `:exact` and
  `:ef_search` (see the moduledoc). Returns result maps sorted best-first, or
  `[]` if nothing is embedded yet.
  """
  def search(query_text, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    vector = query_vector(query_text, opts)

    Logger.info("Semantic: searching top_k=#{top_k}#{mode_label(opts)}")
    run_query(vector, top_k, opts) |> Search.to_results()
  end

  # Where the query's vector comes from:
  #   * a stored %Pgvector{} (eval passes query.embedding) — use as-is
  #   * a plain list of floats — wrap it
  #   * nothing — embed the text live via OpenAI (one call). Logged loudly so a
  #     forgotten `mix rag.embed` shows up as 300 live calls in an eval, not a
  #     silent surprise.
  defp query_vector(query_text, opts) do
    case Keyword.get(opts, :query_embedding) do
      %Pgvector{} = vector ->
        vector

      list when is_list(list) ->
        Pgvector.new(list)

      nil ->
        Logger.info(
          "Semantic: no stored embedding — embedding the query live via #{inspect(Embed.embedder())}"
        )

        # Calls OpenAI api to prepare embedding
        [vector] = Embed.embed([query_text])
        Pgvector.new(vector)
    end
  end

  # Default: let Postgres choose the plan (exact scan, or the HNSW index once it
  # exists). The two pinned modes wrap the query in a transaction so the
  # per-connection setting actually applies to it (SET LOCAL / set_config local).
  defp run_query(vector, top_k, opts) do
    cond do
      Keyword.get(opts, :exact, false) ->
        with_local_setting(
          fn ->
            # Disabling index scans forces the full sequential scan = true
            # nearest neighbors, the exact baseline HNSW is compared against.
            Repo.query!("SELECT set_config('enable_indexscan', 'off', true)")
          end,
          vector,
          top_k
        )

      ef = Keyword.get(opts, :ef_search) ->
        with_local_setting(
          fn ->
            # ef_search = size of the HNSW candidate list: bigger = higher recall,
            # slower. Passed as a bind param (set_config takes text), never spliced.
            Repo.query!("SELECT set_config('hnsw.ef_search', $1, true)", [Integer.to_string(ef)])
          end,
          vector,
          top_k
        )

      true ->
        Repo.query!(@sql, [vector, top_k])
    end
  end

  defp with_local_setting(apply_setting, vector, top_k) do
    {:ok, result} =
      Repo.transaction(fn ->
        apply_setting.()
        Repo.query!(@sql, [vector, top_k])
      end)

    result
  end

  defp mode_label(opts) do
    cond do
      Keyword.get(opts, :exact, false) -> " (exact)"
      ef = Keyword.get(opts, :ef_search) -> " (hnsw ef_search=#{ef})"
      true -> ""
    end
  end
end
