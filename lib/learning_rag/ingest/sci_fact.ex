defmodule LearningRag.Ingest.SciFact do
  @moduledoc """
  Parsers for the SciFact dataset in BEIR's standard layout:

      corpus.jsonl      one JSON doc per line: `_id`, `title`, `text`
      queries.jsonl     one JSON query per line: `_id`, `text`
      qrels/test.tsv    header + rows of `query-id <TAB> corpus-id <TAB> score`

  We load ONLY `qrels/test.tsv` and the queries it references (300 of the
  1,109 in queries.jsonl — the rest belong to the train split). Published
  BEIR baselines are computed on exactly this test split, which is what makes
  our evaluation numbers comparable to theirs.

  All ids stay strings end-to-end — they're identifiers, not numbers.
  """

  @doc "Streams `%{external_id, title, body}` maps from a BEIR corpus.jsonl."
  def parse_corpus(path) do
    path
    |> File.stream!()
    |> Stream.map(&parse_corpus_line/1)
  end

  @doc "Streams `%{external_id, text}` maps from a BEIR queries.jsonl."
  def parse_queries(path) do
    path
    |> File.stream!()
    |> Stream.map(&parse_query_line/1)
  end

  @doc "Parses a BEIR qrels TSV into `%{query_external_id, doc_external_id, relevance}` maps."
  def parse_qrels(path) do
    path
    |> File.stream!()
    # First line is the column header: "query-id\tcorpus-id\tscore".
    |> Stream.drop(1)
    |> Enum.map(&parse_qrel_line/1)
  end

  @doc false
  def parse_corpus_line(line) do
    %{"_id" => id, "title" => title, "text" => text} = Jason.decode!(line)
    %{external_id: id, title: title, body: text}
  end

  @doc false
  def parse_query_line(line) do
    %{"_id" => id, "text" => text} = Jason.decode!(line)
    %{external_id: id, text: text}
  end

  @doc false
  def parse_qrel_line(line) do
    [query_id, doc_id, score] = line |> String.trim_trailing() |> String.split("\t")
    %{query_external_id: query_id, doc_external_id: doc_id, relevance: String.to_integer(score)}
  end
end
