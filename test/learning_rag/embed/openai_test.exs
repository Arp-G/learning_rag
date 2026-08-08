defmodule LearningRag.Embed.OpenAITest do
  @moduledoc """
  Tests the OpenAI embedder's request/response handling with a stubbed HTTP
  layer (Req.Test) — no network, no API key spend. config/test.exs points the
  module's Req client at `{Req.Test, LearningRag.Embed.OpenAI}`.
  """
  use ExUnit.Case, async: true

  alias LearningRag.Embed.OpenAI

  setup do
    # The module checks the key BEFORE making the HTTP call, so a dummy is
    # needed even though the request itself is stubbed.
    System.put_env("OPENAI_API_KEY", "sk-test")
    on_exit(fn -> System.delete_env("OPENAI_API_KEY") end)
  end

  test "returns one embedding per input, re-ordered to match input order" do
    # Respond with data out of order (index 1 before 0) to prove we sort by index.
    Req.Test.stub(OpenAI, fn conn ->
      Req.Test.json(conn, %{
        "data" => [
          %{"index" => 1, "embedding" => [0.0, 1.0]},
          %{"index" => 0, "embedding" => [1.0, 0.0]}
        ]
      })
    end)

    assert OpenAI.embed(["first", "second"]) == [[1.0, 0.0], [0.0, 1.0]]
  end

  test "raises a clear error when the key is missing" do
    System.delete_env("OPENAI_API_KEY")

    assert_raise RuntimeError, ~r/OPENAI_API_KEY/, fn ->
      OpenAI.embed(["x"])
    end
  end

  test "raises on a non-200 response" do
    Req.Test.stub(OpenAI, fn conn ->
      conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"error" => "rate limited"})
    end)

    assert_raise RuntimeError, ~r/HTTP 429/, fn ->
      OpenAI.embed(["x"])
    end
  end
end
