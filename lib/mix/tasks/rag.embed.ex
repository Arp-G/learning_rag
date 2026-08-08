defmodule Mix.Tasks.Rag.Embed do
  @shortdoc "Embeds chunks + eval queries with OpenAI (fills the vector columns)"

  @moduledoc """
  Computes dense embeddings for every chunk and every eval query, storing them
  in the `embedding` columns for semantic search:

      $ OPENAI_API_KEY=sk-... mix rag.embed

  Needs `OPENAI_API_KEY`. Does NOT touch the sparse (BM25/TF-IDF) index — run
  it any time after `mix rag.index`.

  Idempotent: only rows whose embedding is still NULL are sent, so a re-run just
  fills gaps (e.g. after a partial failure). Embedding the whole SciFact corpus
  (~7.7k chunks, ~1.9M tokens) plus 300 queries costs roughly $0.04.
  """
  use Mix.Task

  import Ecto.Query

  alias LearningRag.{Repo, Embed}
  alias LearningRag.Corpus.Chunk
  alias LearningRag.Eval.Query

  @requirements ["app.start"]

  # Texts per OpenAI request. Small enough to stay well under the API's
  # per-request token cap (~300k) at ~250 tokens/chunk, and to keep each
  # network failure cheap to retry.
  @batch_size 100

  @impl Mix.Task
  def run(_args) do
    embed_table(Chunk, "chunks")
    embed_table(Query, "queries")
  end

  # Repeatedly grab a batch of not-yet-embedded rows and embed them, until
  # none remain. Because each pass only selects `embedding IS NULL`, the work
  # shrinks every round and stops cleanly at zero.
  defp embed_table(schema, label) do
    total = drain(schema, label, 0)
    Mix.shell().info("#{label}: embedded #{total} rows this run")
  end

  defp drain(schema, label, total) do
    rows =
      Repo.all(
        from r in schema,
          where: is_nil(r.embedding),
          select: %{id: r.id, text: r.text},
          limit: @batch_size
      )

    case rows do
      # No un-embedded rows left — also avoids sending OpenAI an empty input.
      [] ->
        total

      rows ->
        vectors = Embed.embed(Enum.map(rows, & &1.text))
        write_back(schema, rows, vectors)
        total = total + length(rows)
        Mix.shell().info("#{label}: +#{length(rows)} embedded (#{total} so far)")
        drain(schema, label, total)
    end
  end

  # Persist each row's vector. One targeted UPDATE per row inside a transaction:
  # simple and clear, and network time dwarfs it anyway. (A faster bulk form is
  # `UPDATE ... FROM unnest($1::bigint[], $2::vector[])` — a single round-trip
  # per batch — but it's not worth the added complexity at this scale.)
  defp write_back(schema, rows, vectors) do
    Repo.transaction(fn ->
      rows
      |> Enum.zip(vectors)
      |> Enum.each(fn {row, vector} ->
        from(r in schema, where: r.id == ^row.id)
        |> Repo.update_all(set: [embedding: Pgvector.new(vector)])
      end)
    end)
  end
end
