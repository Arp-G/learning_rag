defmodule LearningRag.Search.FusionTest do
  use ExUnit.Case, async: true

  alias LearningRag.Search.Fusion

  describe "rrf/2" do
    test "sums 1/(k + rank) across lists, best first" do
      # List 1: [1, 2, 3]   List 2: [2, 1, 4]   (k = 60, ranks are 1-based)
      #   1: 1/61 + 1/62   2: 1/62 + 1/61   3: 1/63   4: 1/63
      # So 1 and 2 tie (top), 3 and 4 tie (below); id breaks ties ascending.
      result = Fusion.rrf([[1, 2, 3], [2, 1, 4]], 60)

      assert Enum.map(result, &elem(&1, 0)) == [1, 2, 3, 4]

      scores = Map.new(result)
      assert_in_delta scores[1], 1 / 61 + 1 / 62, 1.0e-12
      assert_in_delta scores[2], 1 / 61 + 1 / 62, 1.0e-12
      assert_in_delta scores[3], 1 / 63, 1.0e-12
      assert_in_delta scores[4], 1 / 63, 1.0e-12
    end

    test "an item in both lists beats an item in only one" do
      # 1 is in both; 9 is only in the second list at rank 1.
      #   1: 1/61 (rank1) + 1/62 (rank2) ≈ 0.0325
      #   9: 1/61 ≈ 0.0164
      result = Fusion.rrf([[1, 2], [9, 1]], 60)
      assert hd(result) |> elem(0) == 1
    end
  end

  describe "weighted/1" do
    test "min-max normalizes each list then takes the weighted sum" do
      # List 1 (weight 0.5): {1:10, 2:6, 3:2} -> norm {1:1.0, 2:0.5, 3:0.0}
      # List 2 (weight 0.5): {2:1, 3:0.5, 4:0} -> norm {2:1.0, 3:0.5, 4:0.0}
      # Weighted sum:
      #   1: .5*1.0                = 0.5
      #   2: .5*0.5 + .5*1.0       = 0.75
      #   3: .5*0.0 + .5*0.5       = 0.25
      #   4:          .5*0.0       = 0.0
      result =
        Fusion.weighted([
          {[{1, 10.0}, {2, 6.0}, {3, 2.0}], 0.5},
          {[{2, 1.0}, {3, 0.5}, {4, 0.0}], 0.5}
        ])

      assert Enum.map(result, &elem(&1, 0)) == [2, 1, 3, 4]

      scores = Map.new(result)
      assert_in_delta scores[2], 0.75, 1.0e-12
      assert_in_delta scores[1], 0.5, 1.0e-12
      assert_in_delta scores[3], 0.25, 1.0e-12
      assert_in_delta scores[4], 0.0, 1.0e-12
    end

    test "a single item (zero range) normalizes to 1.0, not a divide-by-zero" do
      assert Fusion.weighted([{[{1, 5.0}], 1.0}]) == [{1, 1.0}]
    end

    test "beta-style weights slide between the two lists" do
      bm25 = [{1, 10.0}, {2, 0.0}]
      sem = [{2, 10.0}, {1, 0.0}]

      # weight all on the first list -> its winner (1) is on top
      assert Fusion.weighted([{bm25, 1.0}, {sem, 0.0}]) |> hd() |> elem(0) == 1
      # weight all on the second list -> its winner (2) is on top
      assert Fusion.weighted([{bm25, 0.0}, {sem, 1.0}]) |> hd() |> elem(0) == 2
    end
  end
end
