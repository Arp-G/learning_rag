defmodule LearningRag.Search.Fusion do
  @moduledoc """
  Two ways to merge several ranked result lists into one — the heart of hybrid
  search. Both are pure functions over chunk ids/scores, so they're easy to
  test and reason about.

  The problem hybrid solves: BM25 and semantic search each return a good ranking,
  but on *different* grounds (exact words vs. meaning), and their scores aren't
  comparable (BM25 is unbounded; cosine similarity is roughly -1..1). Fusion
  combines the two rankings into one that's usually better than either alone.

  ## `rrf/2` — Reciprocal Rank Fusion

  Ignores the raw scores entirely and uses only each item's *rank* (position):

      rrf_score(chunk) = Σ over each list of  1 / (k + rank_in_that_list)

  A chunk near the top of either list gets a big contribution; being absent from
  a list just contributes nothing. Because it only looks at rank, it sidesteps
  the "BM25 and cosine live on different scales" problem completely — which is
  why it's the robust default. `k` (typically 60) softens the emphasis on the
  very top ranks: larger k = flatter, so rank 1 vs rank 2 matters less.

  ## `weighted/1` — weighted, normalized score fusion

  Uses the raw scores, but first squashes each list's scores into 0..1 with
  min-max normalization (so BM25 and cosine become comparable), then takes a
  weighted sum:

      score(chunk) = Σ over each list of  weight_of_list * normalized_score

  Two numbers are in play, at different levels: a *score* is one scorer's raw
  relevance for a single chunk (a BM25 score, a cosine similarity — different
  scales, which is why we normalize first), while a *weight* applies to a whole
  list. The weight is exactly `beta`: hybrid passes `beta` for the semantic list
  and `1 - beta` for BM25, so `beta` dials smoothly from pure BM25 (0) to pure
  semantic (1).
  """

  @doc """
  Reciprocal Rank Fusion of several ranked id lists (each best-first).
  Returns `[{chunk_id, score}]` sorted best-first.

  `:k`— RRF constant (default #{60}); bigger = flatter
  """
  @spec rrf([[term]], number()) :: [{term, float()}] when term: any()
  def rrf(rankings, k) do
    rankings
    # For each ranked list, turn its ids into {id, contribution-from-this-list}.
    |> Enum.flat_map(fn ids ->
      ids
      # Pair each id with its 1-based rank (top item = rank 1).
      |> Enum.with_index(1)
      # Its contribution is 1/(k + rank): top rank gives the most; larger k
      # flattens the gap between ranks.
      |> Enum.map(fn {id, rank} -> {id, 1.0 / (k + rank)} end)
    end)
    # An id can appear in several lists — add up all its contributions.
    |> sum_by_id()
    # Highest total first.
    |> sort_best_first()
  end

  @doc """
  Weighted min-max fusion. Takes `[{scored_list, weight}]` where each
  `scored_list` is `[{chunk_id, score}]` — `score` is a scorer's raw relevance
  per chunk, and `weight` is how much that whole list counts (hybrid passes
  `beta` for semantic, `1 - beta` for BM25). Returns `[{chunk_id, score}]`
  sorted best-first.
  """
  @spec weighted([{[{term, number()}], number()}]) :: [{term, float()}] when term: any()
  def weighted(scored_lists_with_weights) do
    scored_lists_with_weights
    # For each (scored list, weight): scale that list's scores to 0..1, then
    # multiply each by this list's weight → {id, weighted contribution}.
    |> Enum.flat_map(fn {scored, weight} ->
      scored
      # Normalize so BM25's and cosine's different ranges become comparable.
      |> normalize()
      # Apply this list's weight (e.g. beta for semantic, 1 - beta for BM25).
      |> Enum.map(fn {id, norm} -> {id, weight * norm} end)
    end)
    # Same tail as RRF: total each id's contributions across lists, sort.
    |> sum_by_id()
    |> sort_best_first()
  end

  # Min-max scale a list's scores into 0..1. If every score is equal (or there's
  # one item), the range is 0 — treat them all as 1.0 (they're tied at the top of
  # this list, so they should all count fully).
  defp normalize([]), do: []

  defp normalize(scored) do
    # Just the raw scores, to find the low and high ends.
    scores = Enum.map(scored, fn {_id, score} -> score end)
    min = Enum.min(scores)
    max = Enum.max(scores)
    # The spread we'll divide by to land everything in 0..1.
    range = max - min

    Enum.map(scored, fn {id, score} ->
      # Min-max scale: (score - min) / range. If every score is equal (range 0,
      # e.g. a single result), there's no spread — treat them all as 1.0 since
      # they're tied at the top of this list.
      normalized = if range == 0.0 or range == 0, do: 1.0, else: (score - min) / range
      {id, normalized}
    end)
  end

  # Sum contributions per id across all lists.
  defp sum_by_id(pairs) do
    # Fold the {id, value} pairs into a map; when an id repeats, add its values.
    Enum.reduce(pairs, %{}, fn {id, value}, acc ->
      # Seed with `value` the first time we see the id, then keep adding.
      Map.update(acc, id, value, &(&1 + value))
    end)
  end

  defp sort_best_first(score_map) do
    # Sort by {-score, id}: negating the score puts the highest first, and the
    # id breaks ties in a stable, deterministic way (tests rely on it).
    Enum.sort_by(score_map, fn {id, score} -> {-score, id} end)
  end
end
