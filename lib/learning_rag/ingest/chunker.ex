defmodule LearningRag.Ingest.Chunker do
  @moduledoc """
  Splits a document into overlapping windows of words — the passages ("chunks")
  that search actually runs on.

  Why chunk at all? Scoring whole documents is too coarse: a long document
  covering ten topics matches lots of queries a little bit. Chunks give search
  a smaller, focused unit whose words are mostly about one thing.

  Why overlap? A phrase sitting right on a window boundary would get split
  across two chunks and match neither well. Overlapping the windows means every
  stretch of text shows up whole in at least one chunk.

  We stick the title on the front of every chunk. Titles are usually the most
  descriptive words, so repeating them in each chunk lets those words help the
  document match no matter which chunk gets retrieved.

  SciFact abstracts are ~250 words, so most documents here become just 1–2
  chunks. That's fine — chunking gets more interesting later with longer docs.
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
