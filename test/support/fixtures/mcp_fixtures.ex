defmodule Estimate.MCPFixtures do
  @moduledoc "Fixtures for MCP API keys and anubis frames."

  alias Anubis.Server.Frame

  @doc "Enables MCP on the org and generates a key. Returns {plaintext, %APIKey{}}."
  def mcp_api_key_fixture(user, organization) do
    {:ok, _} = Estimate.Organizations.update_mcp_settings(organization, %{mcp_enabled: true})
    {:ok, {plaintext, key}} = Estimate.MCP.generate_api_key(user.id, organization.id)
    {plaintext, key}
  end

  @doc "A frame shaped like anubis builds after successful authorization."
  def mcp_frame(user, organization, role \\ "owner") do
    %Frame{
      context: %Anubis.Server.Context{
        auth: %{
          sub: user.id,
          raw_claims: %{"org_id" => organization.id, "role" => role}
        }
      }
    }
  end
end
