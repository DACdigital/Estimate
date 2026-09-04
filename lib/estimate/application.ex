defmodule Estimate.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Estimate.Encryption.load_keys()

    children = [
      EstimateWeb.Telemetry,
      Estimate.Repo,
      {DNSCluster, query: Application.get_env(:estimate, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Estimate.PubSub},
      {Task.Supervisor, name: Estimate.TaskSupervisor},
      {Estimate.RateLimit, [clean_period: :timer.minutes(1)]},
      Estimate.MCP.OAuth.Janitor,
      EstimateWeb.Endpoint,
      {EstimateWeb.MCPServer,
       transport: :streamable_http, authorization: EstimateWeb.MCPServer.runtime_authorization()}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Estimate.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EstimateWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
