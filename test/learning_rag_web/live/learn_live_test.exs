defmodule LearningRagWeb.LearnLiveTest do
  use LearningRagWeb.ConnCase

  import Phoenix.LiveViewTest

  test "index renders the README with in-app note links", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/learn")

    # sidebar + rendered README content
    assert html =~ "Study notes"
    assert html =~ "The RAG pipeline"
    # a learning-path link has been rewritten from NN-slug.md -> /learn/NN-slug
    assert html =~ ~s(href="/learn/02-tf-idf-and-bm25")
  end

  test "a note renders markdown (heading, table) with rewritten links", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/learn/02-tf-idf-and-bm25")

    # markdown -> HTML: the note's H1 text and at least one GFM table
    assert html =~ "keyword (sparse) retrieval"
    assert html =~ "<table>"

    # sibling-note link rewritten to an in-app route...
    assert html =~ ~s(href="/learn/03-vectors-and-embeddings")
    # ...and no raw .md link leaked through
    refute html =~ ~s(href="03-vectors-and-embeddings.md")

    # code link rewritten to GitHub, opening in a new tab
    assert html =~
             ~s(href="https://github.com/Arp-G/learning_rag/blob/master/lib/learning_rag/search/bm25.ex" target="_blank")
  end

  test "the glossary renders with anchorable section headings", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/learn/glossary")
    assert html =~ "Glossary"
    assert html =~ "Cosine similarity"
    # headings get GitHub-style id slugs so #section anchors resolve in-app
    assert html =~ ~s(<h2 id="searching">)
    assert html =~ ~s(<h2 id="evaluation">)
  end

  test "glossary links deep-link to the relevant section anchor", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/learn/05-searching-algorithms")
    assert html =~ ~s(href="/learn/glossary#searching")
  end

  test "an unknown slug redirects back to the index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/learn"}}} = live(conn, "/learn/does-not-exist")
  end
end
