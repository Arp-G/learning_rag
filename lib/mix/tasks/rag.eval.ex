defmodule Mix.Tasks.Rag.Eval do
  @shortdoc "Evaluates a scorer against SciFact's relevance judgments"

  @moduledoc """
  Runs a scorer over all 300 SciFact test queries and prints the mean IR
  metrics:

      $ mix rag.eval --scorer bm25
      $ mix rag.eval --scorer tfidf
      $ mix rag.eval --scorer bm25 --k1 1.2 --b 0.75

  Options:

      --scorer  bm25 (default) | tfidf | semantic
      --k1      BM25 term-frequency saturation (BM25 only)
      --b       BM25 length normalization      (BM25 only)

  On SciFact, published BM25 gets ~0.665 NDCG@10 — a good target to sanity
  check the BM25 numbers against. Precision looks tiny (~0.1) only because
  SciFact averages ~1.1 relevant documents per query; recall, MRR and NDCG
  are the informative numbers here.
  """
  use Mix.Task

  @requirements ["app.start"]

  @switches [scorer: :string, k1: :float, b: :float]

  @scorers %{
    "bm25" => LearningRag.Search.Bm25,
    "tfidf" => LearningRag.Search.TfIdf,
    "semantic" => LearningRag.Search.Semantic
  }

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("unknown/invalid options: #{inspect(invalid)}")

    scorer =
      Map.get(@scorers, Keyword.get(opts, :scorer, "bm25")) ||
        Mix.raise("--scorer must be bm25, tfidf, or semantic")

    search_opts = Keyword.take(opts, [:k1, :b])

    %{mean: mean, query_count: count} = LearningRag.Eval.Runner.run(scorer, search_opts)

    print_report(scorer, search_opts, count, mean)
  end

  defp print_report(scorer, search_opts, count, mean) do
    params = if search_opts == [], do: "defaults", else: inspect(search_opts)

    Mix.shell().info("""

    #{inspect(scorer)}  (#{params})  over #{count} queries
    ----------------------------------------------------
      Precision@5    #{fmt(mean.p_at_5)}
      Precision@10   #{fmt(mean.p_at_10)}
      Recall@10      #{fmt(mean.r_at_10)}
      MRR@10         #{fmt(mean.mrr_at_10)}
      MAP            #{fmt(mean.map)}
      NDCG@10        #{fmt(mean.ndcg_at_10)}
    """)
  end

  defp fmt(number), do: :erlang.float_to_binary(number, decimals: 4)
end
