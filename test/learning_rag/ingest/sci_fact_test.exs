defmodule LearningRag.Ingest.SciFactTest do
  use ExUnit.Case, async: true

  alias LearningRag.Ingest.SciFact

  test "parses a corpus.jsonl line" do
    line = ~s({"_id": "4983", "title": "A title", "text": "The abstract.", "metadata": {}})

    assert SciFact.parse_corpus_line(line) == %{
             external_id: "4983",
             title: "A title",
             body: "The abstract."
           }
  end

  test "parses a queries.jsonl line, id stays a string" do
    line =
      ~s({"_id": "1", "text": "0-dimensional biomaterials lack inductive properties.", "metadata": {}})

    assert %{external_id: "1", text: "0-dimensional" <> _} = SciFact.parse_query_line(line)
  end

  test "parses a qrels TSV line including the trailing newline" do
    assert SciFact.parse_qrel_line("1\t31715818\t1\n") == %{
             query_external_id: "1",
             doc_external_id: "31715818",
             relevance: 1
           }
  end

  test "parse_qrels skips the header row" do
    path =
      Path.join(System.tmp_dir!(), "qrels_test_#{System.unique_integer([:positive])}.tsv")

    File.write!(path, "query-id\tcorpus-id\tscore\n1\t100\t1\n2\t200\t1\n")
    on_exit(fn -> File.rm!(path) end)

    assert [
             %{query_external_id: "1", doc_external_id: "100", relevance: 1},
             %{query_external_id: "2", doc_external_id: "200", relevance: 1}
           ] = SciFact.parse_qrels(path)
  end
end
