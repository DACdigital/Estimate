defmodule EstimateWeb.MCPServer do
  @moduledoc """
  Read-only MCP server. Auth: per-user org-scoped API keys (Bearer),
  validated by `Estimate.MCP.KeyValidator`. Every tool runs inside the
  caller's RLS context via `EstimateWeb.MCP.Scope.with_scope/2`.
  """

  use Anubis.Server,
    name: "estimate",
    version: Mix.Project.config()[:version],
    capabilities: [:tools],
    authorization: [
      # Fallback only; application.ex passes runtime_authorization/0 with
      # real URLs. Header-auth clients (Claude Code/Desktop, Cursor) never
      # read the RFC 9728 metadata these feed.
      authorization_servers: ["urn:estimate:none"],
      resource: "urn:estimate:mcp",
      validator: {Estimate.MCP.KeyValidator, []}
    ]

  component(EstimateWeb.MCP.Tools.ListCustomers)
  component(EstimateWeb.MCP.Tools.GetCustomer)
  component(EstimateWeb.MCP.Tools.ListProjects)
  component(EstimateWeb.MCP.Tools.GetProject)
  component(EstimateWeb.MCP.Tools.ListEstimations)
  component(EstimateWeb.MCP.Tools.GetEstimation)
  component(EstimateWeb.MCP.Tools.ListTemplates)
  component(EstimateWeb.MCP.Tools.GetTemplate)
  component(EstimateWeb.MCP.Tools.ListRoleTemplates)
  component(EstimateWeb.MCP.Tools.ListCurrencies)
  component(EstimateWeb.MCP.Tools.Search)

  # --- Write tools ---
  component(EstimateWeb.MCP.Tools.CreateCustomer)
  component(EstimateWeb.MCP.Tools.UpdateCustomer)
  component(EstimateWeb.MCP.Tools.CreateProject)
  component(EstimateWeb.MCP.Tools.UpdateProject)
  component(EstimateWeb.MCP.Tools.CreateEstimation)
  component(EstimateWeb.MCP.Tools.UpdateEstimation)

  @doc "Scheme://host[:port] from endpoint config — safe before the endpoint starts."
  def base_url do
    cfg = Application.get_env(:estimate, EstimateWeb.Endpoint, [])
    url = cfg[:url] || []
    scheme = to_string(url[:scheme] || "http")
    host = url[:host] || "localhost"
    port = url[:port] || (cfg[:http] || [])[:port] || 4000

    if {scheme, port} in [{"https", 443}, {"http", 80}] do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  def mcp_url, do: base_url() <> "/mcp"

  @doc "Child-spec authorization opts with real runtime URLs (overrides the compile-time fallback)."
  def runtime_authorization do
    [
      authorization_servers: [base_url()],
      resource: mcp_url(),
      validator: {Estimate.MCP.KeyValidator, []}
    ]
  end
end
