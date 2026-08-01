defmodule Mix.Tasks.Rag.Index do
  @shortdoc "Loads + chunks + indexes the SciFact dataset into Postgres"

  @moduledoc """
  Builds the searchable index from the downloaded SciFact files:

      $ mix rag.index

  Wipes and rebuilds the tables, so it's safe to re-run (e.g. after changing
  the chunker). Requires `mix rag.download` to have run first, and the
  database to be up.
  """
  use Mix.Task

  @requirements ["app.start"]

  @data_dir "priv/data/scifact"

  @impl Mix.Task
  def run(_args) do
    unless File.exists?(Path.join(@data_dir, "corpus.jsonl")) do
      Mix.raise("SciFact data not found in #{@data_dir}. Run `mix rag.download` first.")
    end

    LearningRag.Ingest.Indexer.run(@data_dir)
  end
end
