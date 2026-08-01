defmodule LearningRag.Eval.Qrel do
  @moduledoc """
  One relevance judgment ("qrel"): for `query`, `document` counts as relevant
  with score `relevance`. Human experts wrote these — they're the answer key
  every metric checks a ranking against.

  In SciFact every relevant document just gets a 1 (relevant or not, nothing
  in between). NDCG can handle graded scores too, but here they're all 1.

  Remember qrels are about DOCUMENTS, but search returns CHUNKS — the eval
  runner maps each chunk hit back to its document (keeping the best chunk per
  document) before grading against these rows.
  """
  use Ecto.Schema

  schema "qrels" do
    field :relevance, :integer

    belongs_to :query, LearningRag.Eval.Query
    belongs_to :document, LearningRag.Corpus.Document
  end
end
