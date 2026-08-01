defmodule LearningRag.Ingest.ChunkerTest do
  use ExUnit.Case, async: true

  alias LearningRag.Ingest.Chunker

  # Synthetic body of n distinct words: "w1 w2 ... wn" — lets every assertion
  # pin down exactly which words landed in which window.
  defp body(n), do: Enum.map_join(1..n, " ", &"w#{&1}")

  # Words of a chunk produced with a nil title (no title line to strip).
  defp chunk_words(chunk), do: String.split(chunk.text)

  describe "windowing (no title)" do
    test "empty body and no title -> no chunks" do
      assert Chunker.chunk(nil, "") == []
      assert Chunker.chunk(nil, "   ") == []
      assert Chunker.chunk("", nil) == []
    end

    test "1 word -> one chunk" do
      assert [%{chunk_index: 0, text: "w1"}] = Chunker.chunk(nil, body(1))
    end

    test "199 and exactly 200 words -> one chunk containing every word" do
      for n <- [199, 200] do
        assert [chunk] = Chunker.chunk(nil, body(n))
        assert chunk_words(chunk) == String.split(body(n))
      end
    end

    test "201 words -> two chunks with a 40-word overlap" do
      assert [c0, c1] = Chunker.chunk(nil, body(201))

      # First window: w1..w200. Second starts at stride 160 (0-based index),
      # i.e. w161, and runs to the end: 40 overlapping words + 1 new one.
      assert chunk_words(c0) == Enum.map(1..200, &"w#{&1}")
      assert chunk_words(c1) == Enum.map(161..201, &"w#{&1}")
      assert c0.chunk_index == 0
      assert c1.chunk_index == 1
    end

    test "360 words -> two chunks, second covers w161..w360" do
      assert [c0, c1] = Chunker.chunk(nil, body(360))
      assert chunk_words(c0) == Enum.map(1..200, &"w#{&1}")
      assert chunk_words(c1) == Enum.map(161..360, &"w#{&1}")
    end

    test "361 words -> three chunks (third window adds w361)" do
      assert [c0, c1, c2] = Chunker.chunk(nil, body(361))
      assert chunk_words(c0) == Enum.map(1..200, &"w#{&1}")
      assert chunk_words(c1) == Enum.map(161..360, &"w#{&1}")
      assert chunk_words(c2) == Enum.map(321..361, &"w#{&1}")
    end

    test "no fully-contained duplicate final window at an exact boundary" do
      # 200 + 160 = 360 words fit exactly into two windows; a third window
      # (w321..w360) would add nothing and must not be emitted.
      assert length(Chunker.chunk(nil, body(360))) == 2
    end
  end

  describe "title handling" do
    test "title is prepended to every chunk" do
      assert [c0, c1] = Chunker.chunk("My Title", body(201))
      assert String.starts_with?(c0.text, "My Title\n\n")
      assert String.starts_with?(c1.text, "My Title\n\n")
    end

    test "title-only document -> one chunk of just the title" do
      assert [%{chunk_index: 0, text: "Only a Title"}] = Chunker.chunk("Only a Title", "")
    end

    test "whitespace title is treated as absent" do
      assert [%{text: "w1"}] = Chunker.chunk("   ", body(1))
    end
  end
end
