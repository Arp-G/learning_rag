defmodule Mix.Tasks.Rag.Search do
  @shortdoc "Runs a sparse-retrieval search from the command line"

  @moduledoc """
  Searches the indexed corpus and prints ranked results with a per-term score
  breakdown:

      $ mix rag.search "vitamin D deficiency and bone fractures"
      $ mix rag.search "..." --scorer tfidf
      $ mix rag.search "..." --scorer bm25 --k1 1.2 --b 0.75 --top 5

  Options:

      --scorer  bm25 (default) | tfidf | semantic
      --k1      BM25 term-frequency saturation (BM25 only, default 1.2)
      --b       BM25 length normalization      (BM25 only, default 0.75)
      --top     number of results to show      (default 10)
  """
  use Mix.Task

  @requirements ["app.start"]

  @switches [scorer: :string, k1: :float, b: :float, top: :integer]

  @scorers %{
    "bm25" => LearningRag.Search.Bm25,
    "tfidf" => LearningRag.Search.TfIdf,
    "semantic" => LearningRag.Search.Semantic
  }

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("unknown/invalid options: #{inspect(invalid)}")

    query =
      case argv do
        [q] ->
          q

        _ ->
          Mix.raise(
            ~s(usage: mix rag.search "query" [--scorer bm25|tfidf] [--k1 1.2] [--b 0.75] [--top 10])
          )
      end

    scorer =
      Map.get(@scorers, Keyword.get(opts, :scorer, "bm25")) ||
        Mix.raise("--scorer must be bm25, tfidf, or semantic")

    search_opts =
      opts
      |> Keyword.take([:k1, :b])
      |> Keyword.put(:top_k, Keyword.get(opts, :top, 10))

    query
    |> scorer.search(search_opts)
    |> print_results(scorer)
  end

  defp print_results([], scorer) do
    Mix.shell().info("\n#{inspect(scorer)}: no results.\n")
  end

  defp print_results(results, scorer) do
    Mix.shell().info("\n#{inspect(scorer)} — #{length(results)} results\n")

    results
    |> Enum.with_index(1)
    |> Enum.each(fn {result, rank} ->
      Mix.shell().info(
        "#{String.pad_leading(to_string(rank), 2)}. " <>
          "score=#{fmt(result.score)}  doc=#{result.doc_external_id}  " <>
          "chunk=#{result.chunk_index}\n    #{truncate(result.title, 90)}"
      )

      # The per-term breakdown: how each query term added up to the score.
      Enum.each(result.breakdown, fn term ->
        Mix.shell().info(
          "      #{String.pad_trailing(term["term"], 16)} " <> breakdown_line(term)
        )
      end)

      Mix.shell().info("")
    end)
  end

  # BM25 rows carry tf_part; TF-IDF rows don't. Show whichever is present.
  defp breakdown_line(%{"tf_part" => tf_part} = term) do
    "tf=#{term["tf"]}  idf=#{fmt(term["idf"])}  tf_part=#{fmt(tf_part)}  contribution=#{fmt(term["contribution"])}"
  end

  defp breakdown_line(term) do
    "tf=#{term["tf"]}  idf=#{fmt(term["idf"])}  contribution=#{fmt(term["contribution"])}"
  end

  defp fmt(number) when is_float(number), do: :erlang.float_to_binary(number, decimals: 4)
  defp fmt(number), do: to_string(number)

  defp truncate(nil, _length), do: ""

  defp truncate(string, length) do
    if String.length(string) > length, do: String.slice(string, 0, length) <> "…", else: string
  end
end
