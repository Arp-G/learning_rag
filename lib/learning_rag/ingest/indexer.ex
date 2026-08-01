defmodule LearningRag.Ingest.Indexer do
  @moduledoc """
  Turns the downloaded SciFact files into a searchable index in Postgres.

  The pipeline, each stage logged with a count and a duration:

      1. reset         wipe the five tables so the task is re-runnable
      2. documents     load corpus.jsonl → documents, chunk each → chunks
      3. postings      build the inverted index from chunks (one SQL statement)
      4. token counts  backfill chunks.token_count from the postings
      5. eval data     load the test queries + their relevance judgments

  Everything after step 2 is plain SQL so the mechanics stay inspectable — you
  can `SELECT * FROM postings` afterwards and see the sparse matrix directly.
  """
  require Logger

  alias LearningRag.Repo
  alias LearningRag.Corpus.{Document, Chunk}
  alias LearningRag.Eval.{Query, Qrel}
  alias LearningRag.Ingest.{SciFact, Chunker}

  # Rows per insert_all. Kept well under Postgres's 65,535 bind-parameter
  # ceiling (500 docs × 6 fields = 3,000 params).
  @batch_size 500

  # Raw SQL can run long on a cold cache; the default 15s is too tight for the
  # whole-corpus postings build.
  @sql_timeout 300_000

  @doc """
  Runs the full indexing pipeline against the SciFact files in `data_dir`.
  """
  def run(data_dir \\ "priv/data/scifact") do
    corpus_path = Path.join(data_dir, "corpus.jsonl")
    queries_path = Path.join(data_dir, "queries.jsonl")
    qrels_path = Path.join([data_dir, "qrels", "test.tsv"])

    reset!()
    doc_map = load_documents(corpus_path)
    build_postings!()
    backfill_token_counts!()
    load_eval_data(queries_path, qrels_path, doc_map)

    Logger.info("Indexing complete.")
    :ok
  end

  # --- Step 1: reset -------------------------------------------------------

  defp reset! do
    # One CASCADE truncate clears all five tables regardless of FK order and
    # resets the id sequences, so `mix rag.index` always starts from scratch.
    Repo.query!("TRUNCATE qrels, queries, postings, chunks, documents RESTART IDENTITY CASCADE")
    Logger.info("Reset all tables.")
  end

  # --- Step 2: documents + chunks -----------------------------------------

  defp load_documents(corpus_path) do
    {microseconds, {doc_count, chunk_count, doc_map}} =
      :timer.tc(fn ->
        SciFact.parse_corpus(corpus_path)
        |> Stream.chunk_every(@batch_size)
        |> Enum.reduce({0, 0, %{}}, fn batch, {docs, chunks, acc_map} ->
          {batch_map, batch_chunks} = insert_document_batch(batch)
          {docs + length(batch), chunks + batch_chunks, Map.merge(acc_map, batch_map)}
        end)
      end)

    Logger.info("Loaded #{doc_count} documents → #{chunk_count} chunks in #{ms(microseconds)} ms")

    doc_map
  end

  # Inserts one batch of documents, then the chunks cut from them.
  # Returns {%{external_id => document_id}, chunk_count_for_batch}.
  defp insert_document_batch(batch) do
    # insert_all does NOT fill timestamps() — set them ourselves, truncated to
    # seconds (Postgrex rejects microseconds on :utc_datetime columns).
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    doc_rows =
      Enum.map(batch, fn doc ->
        %{
          source: "scifact",
          external_id: doc.external_id,
          title: doc.title,
          body: doc.body,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_n, returned} = Repo.insert_all(Document, doc_rows, returning: [:id, :external_id])
    id_by_external = Map.new(returned, &{&1.external_id, &1.id})

    chunk_rows =
      Enum.flat_map(batch, fn doc ->
        document_id = Map.fetch!(id_by_external, doc.external_id)

        doc.title
        |> Chunker.chunk(doc.body)
        |> Enum.map(fn chunk ->
          %{
            document_id: document_id,
            chunk_index: chunk.chunk_index,
            text: chunk.text,
            token_count: 0
          }
        end)
      end)

    Repo.insert_all(Chunk, chunk_rows)
    {id_by_external, length(chunk_rows)}
  end

  # --- Step 3: postings (the inverted index) ------------------------------

  # to_tsvector('english', text) IS the linguistic pipeline: it tokenizes,
  # drops stopwords, and Snowball-stems (e.g. "imaging" → "imag"). We use
  # Postgres ONLY for that — never ts_rank / @@; all ranking is our own SQL.
  #
  # unnest(tsvector) yields one row per distinct lexeme with its positions
  # array, so cardinality(positions) is that term's frequency in the chunk.
  # Each (term, chunk_id, tf) row is one nonzero cell of the term×chunk matrix.
  #
  # NOTE: the 'english' config here MUST match the one in Search.stem_terms/1.
  # Same function + same config on both sides = query and documents are
  # processed identically, which is what makes matching work at all.
  #
  # (Module attributes must be defined before the functions that read them,
  # or the attribute is nil at that point — a classic Elixir gotcha.)
  @build_postings_sql """
  INSERT INTO postings (term, chunk_id, tf)
  SELECT t.lexeme, c.id, cardinality(t.positions)
  FROM chunks c
  CROSS JOIN LATERAL unnest(to_tsvector('english', c.text)) AS t
  """

  @doc """
  Builds the entire inverted index in one SQL statement. Public so tests can
  index a tiny corpus through the exact same code path.
  """
  def build_postings! do
    {microseconds, %{num_rows: rows}} =
      :timer.tc(fn -> Repo.query!(@build_postings_sql, [], timeout: @sql_timeout) end)

    Logger.info("Built #{rows} postings in #{ms(microseconds)} ms")
  end

  # --- Step 4: token counts -----------------------------------------------

  # A chunk's length (for length normalization) is the sum of tf over its
  # postings — a column sum of the sparse matrix. COALESCE handles a chunk
  # whose every word was a stopword (no postings at all).
  # Relies on the postings(chunk_id) index; without it this is O(chunks × postings).
  @token_count_sql """
  UPDATE chunks
  SET token_count = COALESCE(
    (SELECT sum(tf) FROM postings p WHERE p.chunk_id = chunks.id), 0)
  """

  @doc """
  Backfills each chunk's `token_count` (BM25's |D|) from its postings. Public
  for the same test-reuse reason as `build_postings!/0`.
  """
  def backfill_token_counts! do
    {microseconds, %{num_rows: rows}} =
      :timer.tc(fn -> Repo.query!(@token_count_sql, [], timeout: @sql_timeout) end)

    Logger.info("Set token_count on #{rows} chunks in #{ms(microseconds)} ms")
  end

  # --- Step 5: eval data (queries + qrels) --------------------------------

  defp load_eval_data(queries_path, qrels_path, doc_map) do
    qrels = SciFact.parse_qrels(qrels_path)

    # Load only the queries the test qrels actually reference (≈300 of 1,109).
    referenced_ids = MapSet.new(qrels, & &1.query_external_id)
    query_map = load_referenced_queries(queries_path, referenced_ids)

    qrel_rows =
      Enum.map(qrels, fn qrel ->
        %{
          query_id: Map.fetch!(query_map, qrel.query_external_id),
          # Map.fetch! is deliberate: a qrel pointing at a corpus doc we didn't
          # load is a real data problem, so fail loudly (KeyError names the id)
          # rather than silently dropping the judgment.
          document_id: Map.fetch!(doc_map, qrel.doc_external_id),
          relevance: qrel.relevance
        }
      end)

    Repo.insert_all(Qrel, qrel_rows)
    Logger.info("Loaded #{map_size(query_map)} queries and #{length(qrel_rows)} qrels")
  end

  defp load_referenced_queries(queries_path, referenced_ids) do
    query_rows =
      queries_path
      |> SciFact.parse_queries()
      |> Stream.filter(&MapSet.member?(referenced_ids, &1.external_id))
      |> Enum.map(&%{external_id: &1.external_id, text: &1.text})

    {_n, returned} = Repo.insert_all(Query, query_rows, returning: [:id, :external_id])
    Map.new(returned, &{&1.external_id, &1.id})
  end

  # --- helpers -------------------------------------------------------------

  defp ms(microseconds), do: div(microseconds, 1000)
end
