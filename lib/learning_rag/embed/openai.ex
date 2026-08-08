defmodule LearningRag.Embed.OpenAI do
  @moduledoc """
  Embeds text with OpenAI's `text-embedding-3-small` model (1536 dims) — the
  cheap, capable default (~$0.02 per 1M tokens).

  We call the HTTP API directly with Req rather than pulling in an SDK, so the
  whole request/response is right here to read. The endpoint takes a list of
  strings and returns a matching list of vectors:

      POST https://api.openai.com/v1/embeddings
      Authorization: Bearer <OPENAI_API_KEY>
      { "model": "text-embedding-3-small", "input": ["text a", "text b", ...] }

      -> { "data": [ {"index": 0, "embedding": [...1536 floats...]},
                     {"index": 1, "embedding": [...]}, ... ] }

  Batching (how many texts per call) is the caller's job — see `mix rag.embed`.
  """
  @behaviour LearningRag.Embed.Embedder

  require Logger

  # 1536 dims — must match the vector(1536) columns. Don't pass a `dimensions`
  # override or the stored/queried sizes would diverge.
  @model "text-embedding-3-small"

  @impl LearningRag.Embed.Embedder
  def embed(texts) do
    # Read the key at call time (never a compile-time attribute) so it can be
    # exported per-run, and fail with a clear message if it's missing.
    api_key =
      System.get_env("OPENAI_API_KEY") ||
        raise "OPENAI_API_KEY is not set — export it before running `mix rag.embed`"

    Logger.info("OpenAI: embedding #{length(texts)} texts with #{@model}")

    response =
      Req.post!(req(),
        url: "/v1/embeddings",
        auth: {:bearer, api_key},
        json: %{model: @model, input: texts}
      )

    case response.status do
      200 ->
        # "data" comes back in input order, but sort by "index" defensively so
        # a vector can never be paired with the wrong text.
        response.body["data"]
        |> Enum.sort_by(& &1["index"])
        |> Enum.map(& &1["embedding"])

      status ->
        raise "OpenAI embeddings request failed (HTTP #{status}): #{inspect(response.body)}"
    end
  end

  # Base request. In test, config injects `plug: {Req.Test, __MODULE__}` here so
  # the call is stubbed instead of hitting the network.
  defp req do
    [base_url: "https://api.openai.com", receive_timeout: 60_000]
    |> Keyword.merge(Application.get_env(:learning_rag, :openai_req_options, []))
    |> Req.new()
  end
end
