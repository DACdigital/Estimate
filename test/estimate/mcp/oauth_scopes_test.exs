defmodule Estimate.MCP.OAuth.ScopesTest do
  use Estimate.DataCase, async: true

  alias Estimate.MCP.OAuth.Scopes

  test "absent scope defaults to read" do
    assert Scopes.parse(nil) == {:ok, ["mcp:read"]}
    assert Scopes.parse("") == {:ok, ["mcp:read"]}
  end

  test "read+write parses in canonical order and offline_access is ignored" do
    assert Scopes.parse("mcp:write offline_access mcp:read") == {:ok, ["mcp:read", "mcp:write"]}
    assert Scopes.parse("mcp:write") == {:ok, ["mcp:read", "mcp:write"]}
  end

  test "unknown scope is rejected" do
    assert Scopes.parse("mcp:admin") == {:error, :invalid_scope}
    assert Scopes.parse("mcp:read evil") == {:error, :invalid_scope}
  end

  test "to_string / write? / constants" do
    assert Scopes.join(["mcp:read", "mcp:write"]) == "mcp:read mcp:write"
    assert Scopes.write?("mcp:read mcp:write")
    refute Scopes.write?("mcp:read")
    refute Scopes.write?(["mcp:read"])
    assert Scopes.read_only() == "mcp:read"
    assert Scopes.full() == "mcp:read mcp:write"
  end

  test "codes and tokens have a scope column defaulting to mcp:read" do
    for table <- ~w(oauth_codes oauth_tokens) do
      %{rows: [[default, nullable]]} =
        Estimate.Repo.query!(
          "SELECT column_default, is_nullable FROM information_schema.columns WHERE table_name = $1 AND column_name = 'scope'",
          [table]
        )

      assert default =~ "mcp:read"
      assert nullable == "NO"
    end
  end
end
