defmodule Mix.Tasks.Rag.Download do
  @shortdoc "Downloads the SciFact dataset (BEIR) into priv/data/"

  @moduledoc """
  Fetches the SciFact benchmark corpus + queries + relevance judgments:

      $ mix rag.download

  Idempotent: skips the download if the dataset is already extracted.
  Does not need the database (or the app) running.
  """
  use Mix.Task

  @url "https://public.ukp.informatik.tu-darmstadt.de/thakur/BEIR/datasets/scifact.zip"
  @data_dir "priv/data"

  @impl Mix.Task
  def run(_args) do
    # Only Req (HTTP client) is needed — deliberately NOT app.start, so the
    # download works before the database is even up.
    {:ok, _} = Application.ensure_all_started(:req)

    marker = Path.join([@data_dir, "scifact", "corpus.jsonl"])

    if File.exists?(marker) do
      Mix.shell().info("SciFact already present at #{marker} — skipping download")
    else
      File.mkdir_p!(@data_dir)
      zip_path = Path.join(@data_dir, "scifact.zip")

      Mix.shell().info("Downloading #{@url} (~3 MB)...")
      Req.get!(@url, into: File.stream!(zip_path), receive_timeout: 120_000)

      # Zip entries are prefixed "scifact/", so extracting into priv/data/
      # lands everything under priv/data/scifact/. (:zip wants charlists.)
      {:ok, files} = :zip.unzip(String.to_charlist(zip_path), cwd: String.to_charlist(@data_dir))
      File.rm!(zip_path)

      Mix.shell().info("Extracted #{length(files)} files under #{@data_dir}/scifact/")
      Mix.shell().info("Next: mix rag.index")
    end
  end
end
