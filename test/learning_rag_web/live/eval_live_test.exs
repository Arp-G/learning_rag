defmodule LearningRagWeb.EvalLiveTest do
  use LearningRagWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the eval form and empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/eval")
    assert html =~ "Evaluate"
    assert html =~ "No runs yet"
  end

  test "running a scorer adds a row to the comparison table", %{conn: conn} do
    # The test DB has no SciFact queries loaded, so this evaluates 0 queries —
    # enough to prove the async run wires through and a row is appended.
    {:ok, view, _html} = live(conn, ~p"/eval")

    view
    |> form("#eval-form", eval: %{scorer: "tfidf"})
    |> render_submit()

    html = render_async(view)
    assert html =~ "tfidf"
    assert html =~ ~s(id="run-0")
  end
end
