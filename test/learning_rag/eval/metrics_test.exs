defmodule LearningRag.Eval.MetricsTest do
  use ExUnit.Case, async: true

  alias LearningRag.Eval.Metrics

  # The hand-computed examples live in the doctests themselves.
  doctest LearningRag.Eval.Metrics, import: true

  test "an empty ranking scores 0.0 on every metric" do
    relevance = %{a: 1}

    assert Metrics.precision_at_k([], relevance, 5) == 0.0
    assert Metrics.recall_at_k([], relevance, 5) == 0.0
    assert Metrics.reciprocal_rank([], relevance, 5) == 0.0
    assert Metrics.average_precision([], relevance) == 0.0
    assert Metrics.ndcg_at_k([], relevance, 5) == 0.0
  end

  test "a query with no relevant documents scores 0.0 (no division by zero)" do
    assert Metrics.precision_at_k([:a], %{}, 5) == 0.0
    assert Metrics.recall_at_k([:a], %{}, 5) == 0.0
    assert Metrics.reciprocal_rank([:a], %{}, 5) == 0.0
    assert Metrics.average_precision([:a], %{}) == 0.0
    assert Metrics.ndcg_at_k([:a], %{}, 5) == 0.0
  end

  test "results past the k cutoff do not count" do
    # :b is relevant but sits at rank 3, beyond k = 2.
    relevance = %{b: 1}
    ranked = [:x, :y, :b]

    assert Metrics.precision_at_k(ranked, relevance, 2) == 0.0
    assert Metrics.recall_at_k(ranked, relevance, 2) == 0.0
    assert Metrics.reciprocal_rank(ranked, relevance, 2) == 0.0
    assert Metrics.ndcg_at_k(ranked, relevance, 2) == 0.0
  end
end
