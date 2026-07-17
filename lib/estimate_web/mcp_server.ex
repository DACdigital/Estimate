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
      # No OAuth AS exists; inert values satisfy anubis' required config.
      # Header-auth clients (Claude Code/Desktop, Cursor) never read the
      # RFC 9728 metadata these feed.
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
end
