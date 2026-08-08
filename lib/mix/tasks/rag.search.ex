defmodule Mix.Tasks.Rag.Search do
  @shortdoc "Runs a sparse-retrieval search from the command line"

  @moduledoc """
  Searches the indexed corpus and prints ranked results with a per-term score
  breakdown:

      $ mix rag.search "vitamin D deficiency and bone fractures"
      $ mix rag.search "..." --scorer tfidf
      $ mix rag.search "..." --scorer bm25 --k1 1.2 --b 0.75 --top 5
      $ mix rag.search "..." --scorer hybrid --method rrf --k 60
      $ mix rag.search "..." --scorer hybrid --method weighted --beta 0.7

  Options:

      --scorer  bm25 (default) | tfidf | semantic | hybrid
      --k1      BM25 term-frequency saturation (bm25/hybrid, default 1.2)
      --b       BM25 length normalization      (bm25/hybrid, default 0.75)
      --method  hybrid fusion: rrf (default) | weighted
      --k       RRF constant                   (hybrid rrf, default 60)
      --beta    dense weight 0..1              (hybrid weighted, default 0.5)
      --top     number of results to show      (default 10)
  """
  use Mix.Task

  @requirements ["app.start"]

  @switches [
    scorer: :string,
    k1: :float,
    b: :float,
    top: :integer,
    method: :string,
    k: :integer,
    beta: :float
  ]

  @scorers %{
    "bm25" => LearningRag.Search.Bm25,
    "tfidf" => LearningRag.Search.TfIdf,
    "semantic" => LearningRag.Search.Semantic,
    "hybrid" => LearningRag.Search.Hybrid
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
            ~s(usage: mix rag.search "query" [--scorer bm25|tfidf|semantic|hybrid] [--k1] [--b] [--method] [--k] [--beta] [--top])
          )
      end

    scorer =
      Map.get(@scorers, Keyword.get(opts, :scorer, "bm25")) ||
        Mix.raise("--scorer must be bm25, tfidf, semantic, or hybrid")

    search_opts =
      opts
      |> Keyword.take([:k1, :b, :method, :k, :beta])
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

      # The breakdown: for sparse scorers, how each query term added up; for
      # hybrid, where the chunk ranked in each scorer.
      Enum.each(result.breakdown, fn entry ->
        Mix.shell().info("      " <> breakdown_line(entry))
      end)

      Mix.shell().info("")
    end)
  end

  # Three breakdown shapes: BM25 term rows (have tf_part), hybrid source rows
  # (have "source"), and TF-IDF term rows (the fallback). Each returns a full,
  # label-prefixed line.
  defp breakdown_line(%{"tf_part" => tf_part} = term) do
    label(term["term"]) <>
      "tf=#{term["tf"]}  idf=#{fmt(term["idf"])}  tf_part=#{fmt(tf_part)}  contribution=#{fmt(term["contribution"])}"
  end

  defp breakdown_line(%{"source" => source} = entry) do
    label(source) <> "rank=#{entry["rank"]}  score=#{fmt(entry["score"])}"
  end

  defp breakdown_line(term) do
    label(term["term"]) <>
      "tf=#{term["tf"]}  idf=#{fmt(term["idf"])}  contribution=#{fmt(term["contribution"])}"
  end

  defp label(text), do: String.pad_trailing(to_string(text), 16) <> " "

  defp fmt(number) when is_float(number), do: :erlang.float_to_binary(number, decimals: 4)
  defp fmt(number), do: to_string(number)

  defp truncate(nil, _length), do: ""

  defp truncate(string, length) do
    if String.length(string) > length, do: String.slice(string, 0, length) <> "…", else: string
  end
end
