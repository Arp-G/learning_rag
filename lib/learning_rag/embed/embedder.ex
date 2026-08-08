defmodule LearningRag.Embed.Embedder do
  @moduledoc """
  The one thing an embedding backend must do: turn a list of texts into a list
  of vectors, one per text, in the same order.

  Keeping this as a behaviour is the swap seam — today the only implementation
  is `LearningRag.Embed.OpenAI`, but a local model (Bumblebee) or a test fake
  can drop in without any caller changing. Callers go through
  `LearningRag.Embed`, never a concrete module.
  """

  @callback embed(texts :: [String.t()]) :: [[float()]]
end
