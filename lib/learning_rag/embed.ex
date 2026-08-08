defmodule LearningRag.Embed do
  @moduledoc """
  The single entry point for turning text into embedding vectors.

  Everything that needs embeddings calls `LearningRag.Embed.embed/1` and never
  names a concrete backend. Which backend runs is a config value, so tests
  point it at a fake and production points it at OpenAI — no caller changes.
  """

  @doc "Embeds a list of texts, returning one vector per text in the same order."
  @spec embed([String.t()]) :: [[float()]]
  def embed(texts), do: embedder().embed(texts)

  @doc "The configured embedding backend (defaults to OpenAI)."
  def embedder, do: Application.get_env(:learning_rag, :embedder, LearningRag.Embed.OpenAI)
end
