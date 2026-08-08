defmodule LearningRag.Search.Hybrid do
  @moduledoc """
  Hybrid search: run BM25 (keywords) and semantic (meaning) over the same query,
  then merge their two rankings into one. The idea is that the two methods make
  *different* mistakes — BM25 misses paraphrases, semantic misses exact terms —
  so combining them usually beats either alone.

  This scorer doesn't do any new ranking of its own. It calls the existing
  `Bm25` and `Semantic` scorers (unchanged), pulls a top candidates from
  each, and hands the two lists to `LearningRag.Search.Fusion`, which does the
  actual merge. Same `search(query_text, opts)` shape and same result keys as
  the other scorers, so it drops straight into the eval runner and CLI.

  ## Options

    * `:method` — `"rrf"` (default) or `"weighted"` (see `Fusion` for the math)
    * `:k`      — RRF constant (default #{60}); bigger = flatter, flattens the list reducing effect of higher ranks
    * `:beta`   — weighted fusion's dense weight (default #{0.5}); 0 = pure BM25,
      1 = pure semantic
    * `:top_k`, plus `:k1`/`:b` (forwarded to BM25) and `:query_embedding`
      (forwarded to semantic)

  Each result's `breakdown` shows where the chunk sat in each scorer (its rank
  and raw score), so you can see *why* it surfaced — e.g. "semantic loved it,
  BM25 didn't".
  """
  require Logger

  alias LearningRag.Search.{Bm25, Semantic, Fusion}

  @default_method "rrf"
  @default_k 60
  @default_beta 0.5
  @default_top_k 10

  # Candidates to pull from EACH scorer before fusing. Comfortably larger than a
  # typical top_k so a chunk ranked deep by one scorer but high by the other is
  # still in the pool to be rescued.
  @pool 100

  def search(query_text, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    pool = max(@pool, top_k)

    # Forward only the options each scorer understands, and only when present —
    # passing `k1: nil` would override BM25's default with nil.
    bm25_opts = opts |> Keyword.take([:k1, :b]) |> Keyword.put(:top_k, pool)

    # An HNSW search returns at most `ef_search` rows, so to actually fill a pool
    # of `pool` candidates we must ask for at least that much effort — otherwise
    # the semantic list is capped at the default ef_search (40) and comes back
    # shallower than the BM25 list, skewing the fusion.
    sem_opts =
      opts
      |> Keyword.take([:query_embedding])
      |> Keyword.put(:top_k, pool)
      |> Keyword.put(:ef_search, pool)

    bm25_results = Bm25.search(query_text, bm25_opts)
    sem_results = Semantic.search(query_text, sem_opts)

    Logger.info(
      "Hybrid: bm25=#{length(bm25_results)} semantic=#{length(sem_results)} → fuse (#{describe(opts)})"
    )

    bm25_results
    |> fuse(sem_results, opts)
    |> Enum.take(top_k)
    |> hydrate(bm25_results, sem_results)
  end

  defp fuse(bm25_results, sem_results, opts) do
    case Keyword.get(opts, :method, @default_method) do
      "rrf" ->
        k = Keyword.get(opts, :k, @default_k)
        Fusion.rrf([ids(bm25_results), ids(sem_results)], k)

      "weighted" ->
        beta = Keyword.get(opts, :beta, @default_beta)
        # semantic weighted by beta, BM25 by the remainder.
        Fusion.weighted([{scored(bm25_results), 1 - beta}, {scored(sem_results), beta}])

      other ->
        raise ArgumentError,
              "unknown hybrid method #{inspect(other)} (use \"rrf\" or \"weighted\")"
    end
  end

  defp ids(results), do: Enum.map(results, & &1.chunk_id)
  defp scored(results), do: Enum.map(results, &{&1.chunk_id, &1.score})

  # Turn the fused [{chunk_id, fused_score}] back into full result maps: the
  # display fields from whichever scorer saw the chunk, the fused score, and a
  # breakdown showing the chunk's rank + raw score in each scorer.
  defp hydrate(fused, bm25_results, sem_results) do
    by_id = Map.new(bm25_results ++ sem_results, &{&1.chunk_id, &1})
    bm25_rank = rank_map(bm25_results)
    sem_rank = rank_map(sem_results)
    bm25_score = score_map(bm25_results)
    sem_score = score_map(sem_results)

    Enum.map(fused, fn {chunk_id, score} ->
      breakdown =
        [
          source_entry("bm25", chunk_id, bm25_rank, bm25_score),
          source_entry("semantic", chunk_id, sem_rank, sem_score)
        ]
        |> Enum.reject(&is_nil/1)

      by_id
      |> Map.fetch!(chunk_id)
      |> Map.put(:score, score)
      |> Map.put(:breakdown, breakdown)
    end)
  end

  defp rank_map(results) do
    results |> Enum.with_index(1) |> Map.new(fn {result, rank} -> {result.chunk_id, rank} end)
  end

  defp score_map(results), do: Map.new(results, &{&1.chunk_id, &1.score})

  defp source_entry(source, chunk_id, rank_map, score_map) do
    case Map.get(rank_map, chunk_id) do
      nil -> nil
      rank -> %{"source" => source, "rank" => rank, "score" => Map.get(score_map, chunk_id)}
    end
  end

  defp describe(opts) do
    case Keyword.get(opts, :method, @default_method) do
      "weighted" -> "weighted beta=#{Keyword.get(opts, :beta, @default_beta)}"
      _ -> "rrf k=#{Keyword.get(opts, :k, @default_k)}"
    end
  end
end
