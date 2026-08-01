defmodule LearningRag.Eval.Qrel do
  @moduledoc """
  One relevance judgment ("qrel"): for `query`, `document` is relevant with
  grade `relevance`. Human experts made these — they are the ground truth
  every metric compares a ranking against.

  SciFact's grades are all 1 (binary relevance). The graded NDCG formula
  still applies; it just degenerates to the binary case.

  Qrels label DOCUMENTS, but our retrieval returns CHUNKS — the eval runner
  maps each chunk hit to its parent document (keeping the best-ranked chunk
  per document) before grading a ranking against these rows.
  """
  use Ecto.Schema

  schema "qrels" do
    field :relevance, :integer

    belongs_to :query, LearningRag.Eval.Query
    belongs_to :document, LearningRag.Corpus.Document
  end
end
