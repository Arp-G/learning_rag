defmodule LearningRag.Embed.Fake do
  @moduledoc """
  A no-network embedder for tests. Returns a deterministic, non-zero, exactly
  1536-dim vector for every text, so anything that calls `LearningRag.Embed`
  during tests works without hitting OpenAI. `config/test.exs` wires this in.

  (Semantic-search tests mostly bypass this by inserting hand-built vectors
  directly and passing a query vector, but this keeps any stray embed call safe.)
  """
  @behaviour LearningRag.Embed.Embedder

  @impl LearningRag.Embed.Embedder
  def embed(texts) do
    vector = List.duplicate(0.0, 1536) |> List.replace_at(0, 1.0)
    Enum.map(texts, fn _text -> vector end)
  end
end
