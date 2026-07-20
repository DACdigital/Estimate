defmodule Estimate.MCPFixtures do
  @moduledoc "Fixtures for MCP API keys and anubis frames."

  alias Anubis.Server.Frame

  @doc "Enables MCP on the org and generates a key. Returns {plaintext, %APIKey{}, updated_org}."
  def mcp_api_key_fixture(user, organization) do
    {:ok, org} = Estimate.Organizations.update_mcp_settings(organization, %{mcp_enabled: true})
    {:ok, {plaintext, key}} = Estimate.MCP.generate_api_key(user.id, organization.id)
    {plaintext, key, org}
  end

  @doc "Turns on write access for the org and returns the updated struct."
  def enable_mcp_write(organization) do
    {:ok, org} =
      Estimate.Organizations.update_mcp_write_settings(organization, %{mcp_write_enabled: true})

    org
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
