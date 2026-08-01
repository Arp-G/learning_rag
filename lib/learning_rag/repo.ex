defmodule LearningRag.Repo do
  use Ecto.Repo,
    otp_app: :learning_rag,
    adapter: Ecto.Adapters.Postgres
end
