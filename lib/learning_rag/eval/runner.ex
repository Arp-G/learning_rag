defmodule LearningRag.Eval.Runner do
  @moduledoc """
  Runs a scorer over all of SciFact's test queries and averages the scores.

  The one tricky bit: search returns CHUNKS, but the answer key (qrels) is
  about DOCUMENTS. So for each query we:

    1. get a pool of chunks (more than the 10 we grade, because several chunks
       can belong to the same document and collapse into one),
    2. map each chunk to its document, keeping that document's best-ranked
       chunk (results are already sorted by score, so the first time we see a
       document is its best hit),
    3. cut down to the top 10 documents,
    4. compare that document ranking against the query's answer key.

  Then MRR is the average of each query's reciprocal rank, MAP is the average
  of each query's average precision, and so on.
  """
  require Logger

  import Ecto.Query

  alias LearningRag.Repo
  alias LearningRag.Eval.{Query, Metrics}

  # Retrieve this many chunks so that, after collapsing to parent documents,
  # at least @doc_k distinct documents remain (SciFact docs yield 1–2 chunks).
  @chunk_pool 50
  # Rank cutoff for the "@K" metrics and the document list we grade.
  @doc_k 10

  @doc """
  Runs `scorer_module.search/2` over every test query and returns

      %{mean: %{...}, per_query: [%{query_id, metrics}, ...], query_count: n}

  `opts` (e.g. `k1:`, `b:`) are passed straight through to the scorer.
  """
  def run(scorer_module, opts \\ []) do
    queries = load_queries_with_qrels()
    Logger.info("Evaluating #{scorer_module} over #{length(queries)} queries...")

    {microseconds, per_query} =
      :timer.tc(fn ->
        queries
        |> Enum.with_index(1)
        |> Enum.map(fn {{query, relevance}, i} ->
          if rem(i, 50) == 0, do: Logger.info("  #{i}/#{length(queries)}")
          evaluate_query(scorer_module, query, relevance, opts)
        end)
      end)

    Logger.info("Done in #{div(microseconds, 1000)} ms")

    %{
      mean: mean_metrics(per_query),
      per_query: per_query,
      query_count: length(queries)
    }
  end

  # Loads each query together with its relevance judgments as
  # {%Query{}, %{document_id => relevance}}.
  defp load_queries_with_qrels do
    Query
    |> preload(:qrels)
    |> Repo.all()
    |> Enum.map(fn query ->
      relevance = Map.new(query.qrels, &{&1.document_id, &1.relevance})
      {query, relevance}
    end)
  end

  defp evaluate_query(scorer_module, query, relevance, opts) do
    # Turn the query's chunk hits into a ranked list of DOCUMENT ids to grade.
    # Key fact used below: the scorer returns chunks already sorted best-score
    # first (its SQL ends with ORDER BY score DESC).
    ranked_docs =
      query.text
      # search over chunks. Ask for a big pool (not just @doc_k) because several
      # of these chunks can belong to the same document and collapse into one in
      # the next step — we still want @doc_k distinct documents left afterwards.
      |> scorer_module.search(Keyword.put(opts, :top_k, @chunk_pool))
      # Collapse chunks → documents. uniq_by keeps the FIRST row it sees for each
      # document_id and drops the rest. Since the list is sorted best-first, that
      # first row is the document's highest-scoring chunk — so each document is
      # represented once, at its best chunk. (Only correct because it's sorted.)
      |> Enum.uniq_by(& &1.document_id)
      # keep the top @doc_k documents, then reduce each row to just its id.
      |> Enum.take(@doc_k)
      |> Enum.map(& &1.document_id)

    %{
      query_id: query.id,
      metrics: %{
        p_at_5: Metrics.precision_at_k(ranked_docs, relevance, 5),
        p_at_10: Metrics.precision_at_k(ranked_docs, relevance, 10),
        r_at_10: Metrics.recall_at_k(ranked_docs, relevance, 10),
        mrr_at_10: Metrics.reciprocal_rank(ranked_docs, relevance, 10),
        map: Metrics.average_precision(ranked_docs, relevance),
        ndcg_at_10: Metrics.ndcg_at_k(ranked_docs, relevance, 10)
      }
    }
  end

  # Arithmetic mean of each metric across all queries.
  defp mean_metrics([]), do: %{}

  defp mean_metrics(per_query) do
    count = length(per_query)
    metric_keys = per_query |> hd() |> Map.fetch!(:metrics) |> Map.keys()

    Map.new(metric_keys, fn key ->
      total = Enum.reduce(per_query, 0.0, &(&1.metrics[key] + &2))
      {key, total / count}
    end)
  end
end
