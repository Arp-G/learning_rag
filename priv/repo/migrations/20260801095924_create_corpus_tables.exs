defmodule LearningRag.Repo.Migrations.CreateCorpusTables do
  @moduledoc """
  The five tables of the sparse-retrieval phase, in three groups:

    * content:      documents, chunks   (what we ingested / what we search over)
    * search index: postings            (the inverted index — see below)
    * ground truth: queries, qrels      (SciFact's test queries + relevance labels)
  """
  use Ecto.Migration

  def change do
    # The original ingested things, stored as they arrived. Never searched
    # directly — exists for provenance ("where did this result come from?")
    # and so re-chunking never needs a re-download.
    create table(:documents) do
      # Which corpus this came from ("scifact" now, "upload" later).
      add :source, :string, null: false
      # The dataset's own id (BEIR corpus `_id`). Qrels reference documents by
      # this id, so evaluation joins through it.
      add :external_id, :string, null: false
      # :text, not :string — some titles exceed varchar(255).
      add :title, :text
      # Raw abstract text, pre-chunking.
      add :body, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:documents, [:source, :external_id])

    # The retrieval unit. RAG retrieves passages, not whole documents.
    create table(:chunks) do
      add :document_id, references(:documents, on_delete: :delete_all), null: false
      # Position of this chunk within its document (0-based).
      add :chunk_index, :integer, null: false
      add :text, :text, null: false
      # The chunk's stop-worded length: sum of tf over its postings.
      # This is |D| in the BM25 formula (and dl in dl/avgdl).
      add :token_count, :integer, null: false, default: 0
    end

    create unique_index(:chunks, [:document_id, :chunk_index])

    # The inverted index. One row = "term appears in chunk, tf times".
    #
    # Conceptually this table IS the sparse term×chunk matrix from IR theory,
    # stored in coordinate (COO) form: each row is one nonzero cell. Group the
    # rows by chunk_id and you have a chunk's sparse vector; group them by term
    # and you have the inverted index. Same data, two readings.
    #
    # The composite primary key's btree on (term, chunk_id) doubles as the
    # inverted-index access path: prefix-scanning a term yields every chunk
    # containing it — which is exactly what "inverted" means.
    create table(:postings, primary_key: false) do
      add :term, :string, primary_key: true
      add :chunk_id, references(:chunks, on_delete: :delete_all), primary_key: true
      add :tf, :integer, null: false
    end

    # The reverse access path (chunk → its postings). Needed so the
    # token_count backfill and cascade deletes don't seq-scan ~1M rows
    # once per chunk.
    create index(:postings, [:chunk_id])

    # SciFact's 300 test queries — the fixed "exam questions" every evaluation
    # run asks, so metric numbers are comparable across runs (and against
    # published baselines).
    create table(:queries) do
      add :external_id, :string, null: false
      add :text, :text, null: false
    end

    create unique_index(:queries, [:external_id])

    # The answer key ("query relevance judgments"): for query Q, document D is
    # relevant with this grade. Metrics = your ranking vs these rows.
    # Note qrels label DOCUMENTS while retrieval returns CHUNKS — the eval
    # runner maps chunk hits to their parent documents before grading.
    create table(:qrels) do
      add :query_id, references(:queries, on_delete: :delete_all), null: false
      add :document_id, references(:documents, on_delete: :delete_all), null: false
      add :relevance, :integer, null: false
    end

    create unique_index(:qrels, [:query_id, :document_id])
  end
end
