defmodule EstimateWeb.MCP.ScopeTest do
  use ExUnit.Case, async: true

  alias Anubis.Server.Context
  alias Anubis.Server.Frame
  alias EstimateWeb.MCP.Scope

  defp frame(raw_claims) do
    %Frame{
      context: %Context{
        auth: %{sub: Ecto.UUID.generate(), raw_claims: raw_claims}
      }
    }
  end

  describe "claims/1 scope parsing — fails closed" do
    test "malformed (non-binary) scope claim falls back to mcp:read" do
      claims =
        Scope.claims(frame(%{"org_id" => "o", "role" => "member", "scope" => ["mcp:write"]}))

      assert claims.scopes == ["mcp:read"]
    end

    test "absent scope claim falls back to mcp:read" do
      claims = Scope.claims(frame(%{"org_id" => "o", "role" => "member"}))
      assert claims.scopes == ["mcp:read"]
    end
  end
end
