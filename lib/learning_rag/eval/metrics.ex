defmodule LearningRag.Eval.Metrics do
  @moduledoc """
  The standard search-quality metrics, as plain functions over one query's
  results.

  Every function takes the same two things:

    * `ranked`    — the ids your search returned, best first
    * `relevance` — the answer key for this query: `%{id => grade}`, where a
      grade above 0 means relevant (SciFact's grades are all 1)

  and each answers one question about the ranking:

    * `precision_at_k/3` — of my top K, what fraction is relevant?
    * `recall_at_k/3`    — of everything relevant, what fraction made my top K?
    * `reciprocal_rank/3`— how high is the FIRST relevant hit? (1/rank)
    * `average_precision/2` — rewards putting relevant docs early, not just
      somewhere in the top K
    * `ndcg_at_k/3`      — like average precision, but the higher up a relevant
      hit sits the more it counts; this is the number the BEIR benchmark reports

  Each of these scores ONE query. The runner averages them across all queries:
  average of `reciprocal_rank` = MRR, average of `average_precision` = MAP, etc.
  """

  @doc """
  Fraction of the top `k` results that are relevant: `hits / k`.

  Divides by `k` even when fewer than `k` results were returned (the standard
  definition — returning too few results is not rewarded).

      iex> precision_at_k([:a, :b, :c, :d], %{b: 1, x: 1}, 2)
      0.5

      iex> precision_at_k([:a, :b], %{a: 1, b: 1}, 2)
      1.0
  """
  def precision_at_k(ranked, relevance, k) when k > 0 do
    hits(ranked, relevance, k) / k
  end

  @doc """
  Fraction of ALL relevant documents that appear in the top `k`.

  Here `[:a, :b, :c, :d]` found `:b` but missed `:x`, so recall is 1/2:

      iex> recall_at_k([:a, :b, :c, :d], %{b: 1, x: 1}, 4)
      0.5
  """
  def recall_at_k(ranked, relevance, k) when k > 0 do
    case total_relevant(relevance) do
      0 -> 0.0
      total -> hits(ranked, relevance, k) / total
    end
  end

  @doc """
  1/rank of the first relevant result within the top `k`, else 0.0.

  Cares only about how quickly the user meets the FIRST good answer —
  the metric behind "the answer was the second result" (RR = 1/2).

      iex> reciprocal_rank([:a, :b, :c], %{b: 1}, 10)
      0.5

      iex> reciprocal_rank([:a, :b, :c], %{z: 1}, 10)
      0.0
  """
  def reciprocal_rank(ranked, relevance, k) when k > 0 do
    ranked
    |> Enum.take(k)
    |> Enum.find_index(&relevant?(relevance, &1))
    |> case do
      nil -> 0.0
      index -> 1 / (index + 1)
    end
  end

  @doc """
  Mean of precision-at-each-relevant-hit, divided by the TOTAL number of
  relevant documents (so unretrieved relevant docs pull the score down).

  Hits at ranks 1 and 3 → AP = (P@1 + P@3) / 2 = (1/1 + 2/3) / 2 = 5/6:

      iex> average_precision([:a, :b, :c, :d], %{a: 1, c: 1}) |> Float.round(4)
      0.8333

  One hit at rank 2 out of two relevant → AP = (1/2) / 2:

      iex> average_precision([:a, :b, :c, :d], %{b: 1, x: 1})
      0.25

  Note: computed over `ranked` as given. Our runner passes a 10-doc list, so
  the mean of this is MAP@10 — don't compare it to published MAP@1000.
  """
  def average_precision(ranked, relevance) do
    case total_relevant(relevance) do
      0 ->
        0.0

      total ->
        {sum, _hits_so_far} =
          ranked
          |> Enum.with_index(1)
          |> Enum.reduce({0.0, 0}, fn {id, rank}, {sum, hits_so_far} ->
            if relevant?(relevance, id) do
              hits_so_far = hits_so_far + 1
              # Precision at this hit's rank: relevant-so-far / rank.
              {sum + hits_so_far / rank, hits_so_far}
            else
              {sum, hits_so_far}
            end
          end)

        sum / total
    end
  end

  @doc """
  Normalized Discounted Cumulative Gain at `k`.

      DCG@k  = Σ over the top k positions i of  gain(grade_i) / log2(i + 1)
      gain   = 2^grade − 1        (0 for irrelevant, 1 for grade 1, 3 for 2…)
      NDCG@k = DCG@k / IDCG@k     (IDCG = DCG of the best possible ordering)

  The log2 discount means a relevant doc at rank 1 is worth ~1.6x one at
  rank 3, etc. NDCG = 1.0 means "you ordered them as well as possible".

  Only relevant doc sits at rank 2: DCG = 1/log2(3) ≈ 0.6309, and the ideal
  ordering of the two relevant docs gives IDCG = 1/log2(2) + 1/log2(3)
  ≈ 1.6309, so NDCG ≈ 0.6309 / 1.6309:

      iex> ndcg_at_k([:a, :b, :c], %{b: 1, x: 1}, 3) |> Float.round(4)
      0.3869

      iex> ndcg_at_k([:a, :b], %{a: 1, b: 1}, 2)
      1.0

  Graded relevance: putting the grade-1 doc above the grade-2 doc costs you.
  DCG = 1/log2(2) + 3/log2(3), IDCG = 3/log2(2) + 1/log2(3):

      iex> ndcg_at_k([:b, :a], %{a: 2, b: 1}, 2) |> Float.round(4)
      0.7967
  """
  def ndcg_at_k(ranked, relevance, k) when k > 0 do
    dcg =
      ranked
      |> Enum.take(k)
      |> discounted_gain_sum(relevance)

    # Ideal DCG: the same documents' grades in the best possible order.
    idcg =
      relevance
      |> Map.keys()
      |> Enum.sort_by(&Map.fetch!(relevance, &1), :desc)
      |> Enum.take(k)
      |> discounted_gain_sum(relevance)

    if idcg == 0.0, do: 0.0, else: dcg / idcg
  end

  defp discounted_gain_sum(ids, relevance) do
    ids
    |> Enum.with_index(1)
    |> Enum.reduce(0.0, fn {id, rank}, acc ->
      acc + gain(Map.get(relevance, id, 0)) / :math.log2(rank + 1)
    end)
  end

  defp gain(grade), do: :math.pow(2, grade) - 1

  defp relevant?(relevance, id), do: Map.get(relevance, id, 0) > 0

  defp hits(ranked, relevance, k) do
    ranked |> Enum.take(k) |> Enum.count(&relevant?(relevance, &1))
  end

  defp total_relevant(relevance) do
    Enum.count(relevance, fn {_id, grade} -> grade > 0 end)
  end
end
