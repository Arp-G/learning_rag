defmodule Mix.Tasks.Rag.Ann do
  @shortdoc "Compares exact vs HNSW approximate vector search (recall + latency)"

  @moduledoc """
  Measures what the HNSW index buys you and what it costs — the approximate
  nearest-neighbor tradeoff:

      $ mix rag.ann

  For each SciFact query (using its stored embedding), it computes the EXACT
  top-#{10} chunks (full scan) and the APPROXIMATE top-#{10} from the HNSW index
  at several `ef_search` values, then reports:

    * recall@#{10} — fraction of the exact top-#{10} that the approximate search
      also found (1.0 = identical results)
    * mean latency — how long each search took

  Higher `ef_search` → higher recall, slower. At our ~7.7k rows exact is already
  fast, so this is educational: it's the tradeoff that decides everything at
  millions of vectors. Needs `mix rag.embed` and the HNSW index migration.
  """
  use Mix.Task

  import Ecto.Query

  alias LearningRag.Repo
  alias LearningRag.Eval.Query
  alias LearningRag.Search.Semantic

  @requirements ["app.start"]

  @k 10
  @ef_values [10, 40, 100, 200]

  @impl Mix.Task
  def run(_args) do
    queries = load_embedded_queries()

    if queries == [] do
      Mix.raise("No embedded queries found. Run `mix rag.embed` first.")
    end

    # The per-search Logger.info lines would flood 1500 calls — quiet them for
    # the duration, then restore.
    previous_level = Logger.level()
    Logger.configure(level: :warning)

    try do
      {exact_us, exact_by_query} =
        measure(queries, fn q ->
          Semantic.search("", query_embedding: q.embedding, exact: true, top_k: @k)
        end)

      Mix.shell().info("""

      HNSW vs exact over #{length(queries)} queries (top_k=#{@k})
      ------------------------------------------------------------
      exact (full scan)   recall@#{@k}=1.0000   latency=#{fmt_ms(exact_us, queries)} ms
      """)

      for ef <- @ef_values do
        {approx_us, approx_by_query} =
          measure(queries, fn q ->
            Semantic.search("", query_embedding: q.embedding, ef_search: ef, top_k: @k)
          end)

        recall = mean_recall(approx_by_query, exact_by_query)

        Mix.shell().info(
          "hnsw ef_search=#{String.pad_leading(to_string(ef), 3)}   " <>
            "recall@#{@k}=#{fmt(recall)}   latency=#{fmt_ms(approx_us, queries)} ms"
        )
      end

      Mix.shell().info("")
    after
      Logger.configure(level: previous_level)
    end
  end

  defp load_embedded_queries do
    Repo.all(
      from q in Query,
        where: not is_nil(q.embedding),
        select: %{id: q.id, embedding: q.embedding}
    )
  end

  # Run `search_fun` over every query, returning {total_microseconds,
  # %{query_id => [chunk_id]}}.
  defp measure(queries, search_fun) do
    Enum.reduce(queries, {0, %{}}, fn q, {acc_us, acc} ->
      {us, results} = :timer.tc(fn -> search_fun.(q) end)
      {acc_us + us, Map.put(acc, q.id, Enum.map(results, & &1.chunk_id))}
    end)
  end

  # Mean over queries of |approx ∩ exact| / |exact|.
  defp mean_recall(approx_by_query, exact_by_query) do
    query_ids = Map.keys(exact_by_query)

    total =
      Enum.reduce(query_ids, 0.0, fn qid, acc ->
        exact = MapSet.new(exact_by_query[qid])
        approx = MapSet.new(approx_by_query[qid])
        overlap = MapSet.size(MapSet.intersection(exact, approx))
        acc + overlap / max(1, MapSet.size(exact))
      end)

    total / length(query_ids)
  end

  defp fmt_ms(total_us, queries) do
    mean_ms = total_us / length(queries) / 1000
    :erlang.float_to_binary(mean_ms, decimals: 2)
  end

  defp fmt(number), do: :erlang.float_to_binary(number, decimals: 4)
end
