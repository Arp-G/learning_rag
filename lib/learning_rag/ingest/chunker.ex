defmodule LearningRag.Ingest.Chunker do
  @moduledoc """
  Splits a document into fixed-size overlapping word windows — the passages
  ("chunks") that retrieval actually operates on.

  Why chunk at all? Ranking whole documents is too coarse: a long document
  about ten topics would match everything weakly. Chunks give retrieval a
  focused unit whose words are all about the same thing.

  Why overlap? A sentence that straddles a window boundary would otherwise be
  split across two chunks and match neither. Overlap guarantees every
  position of the text appears un-split in at least one chunk.

  The title is prepended to every chunk — a poor man's "field boost": title
  words are usually the most informative, and repeating them in each chunk
  gives them term-frequency credit wherever the document is matched.

  SciFact abstracts run ~250 words, so most documents produce just 1–2
  chunks here. That's expected — chunking gets interesting later, with
  longer documents.
  """

  # Window size and overlap, in whitespace-separated words. Deliberately plain
  # module attributes, not config — change them here, re-run `mix rag.index`.
  @chunk_size_words 200
  @overlap_words 40
  # Each next window starts this many words after the previous one.
  @stride @chunk_size_words - @overlap_words

  @spec chunk(String.t() | nil, String.t() | nil) ::
          [%{chunk_index: non_neg_integer(), text: String.t()}]
  def chunk(title, body) do
    title = String.trim(title || "")
    words = String.split(body || "", ~r/\s+/, trim: true)

    word_windows =
      cond do
        words != [] -> build_windows(words, length(words), 0, [])
        # No body but a title: emit one title-only chunk so the document
        # stays findable at all.
        title != "" -> [[]]
        true -> []
      end

    word_windows
    |> Enum.with_index()
    |> Enum.map(fn {window, index} ->
      %{chunk_index: index, text: assemble(title, Enum.join(window, " "))}
    end)
  end

  # Emit the window starting at `start`, then recurse unless the next window
  # would add nothing new: once `next_start >= count - overlap`, the current
  # window has already covered every remaining word, and continuing would
  # emit a final window fully contained in this one.
  defp build_windows(words, count, start, acc) do
    window = words |> Enum.drop(start) |> Enum.take(@chunk_size_words)
    next_start = start + @stride

    if next_start >= count - @overlap_words do
      Enum.reverse([window | acc])
    else
      build_windows(words, count, next_start, [window | acc])
    end
  end

  defp assemble(title, window_text) do
    [title, window_text]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end
end
