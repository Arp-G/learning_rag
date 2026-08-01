defmodule LearningRag.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LearningRagWeb.Telemetry,
      LearningRag.Repo,
      {DNSCluster, query: Application.get_env(:learning_rag, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LearningRag.PubSub},
      # Start a worker by calling: LearningRag.Worker.start_link(arg)
      # {LearningRag.Worker, arg},
      # Start to serve requests, typically the last entry
      LearningRagWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LearningRag.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LearningRagWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
