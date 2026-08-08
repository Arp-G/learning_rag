defmodule LearningRagWeb.SearchLiveTest do
  use LearningRagWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LearningRag.Repo
  alias LearningRag.Corpus.{Document, Chunk}
  alias LearningRag.Ingest.Indexer

  test "renders the search form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Search"
    assert html =~ "Scorer"
  end

  test "a bm25 search shows matching chunks", %{conn: conn} do
    doc =
      Repo.insert!(%Document{
        source: "test",
        external_id: "d1",
        title: "Cats",
        body: "cat cat dog"
      })

    Repo.insert!(%Chunk{document_id: doc.id, chunk_index: 0, text: "cat cat dog", token_count: 0})
    Indexer.build_postings!()
    Indexer.backfill_token_counts!()

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#search-form", search: %{query: "cat", scorer: "bm25"})
      |> render_submit()

    assert html =~ "Cats"
    assert html =~ "1 results"
  end

  test "an empty query yields no results", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#search-form", search: %{query: "   ", scorer: "bm25"})
      |> render_submit()

    assert html =~ "0 results"
  end
end
