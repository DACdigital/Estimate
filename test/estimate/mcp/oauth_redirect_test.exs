defmodule Estimate.MCP.OAuth.RedirectTest do
  use ExUnit.Case, async: true

  alias Estimate.MCP.OAuth.Redirect

  describe "valid_for_registration?/1" do
    test "accepts https and loopback http" do
      assert Redirect.valid_for_registration?("https://claude.ai/api/mcp/auth_callback")
      assert Redirect.valid_for_registration?("http://localhost/callback")
      assert Redirect.valid_for_registration?("http://localhost:3118/callback")
      assert Redirect.valid_for_registration?("http://127.0.0.1:49152/callback")
    end

    test "rejects everything else" do
      refute Redirect.valid_for_registration?("http://evil.com/callback")
      refute Redirect.valid_for_registration?("http://localhost.evil.com/callback")
      refute Redirect.valid_for_registration?("ftp://localhost/callback")
      refute Redirect.valid_for_registration?("not a uri")
      refute Redirect.valid_for_registration?("https://")
    end

    test "rejects query or fragment components (RFC 6749 §3.1.2 append safety)" do
      refute Redirect.valid_for_registration?("https://claude.ai/cb?x=1")
      refute Redirect.valid_for_registration?("http://localhost/cb#f")
    end
  end

  describe "matches?/2" do
    test "byte-exact for https" do
      registered = ["https://claude.ai/api/mcp/auth_callback"]
      assert Redirect.matches?(registered, "https://claude.ai/api/mcp/auth_callback")
      refute Redirect.matches?(registered, "https://claude.ai/api/mcp/auth_callback/")
      refute Redirect.matches?(registered, "https://claude.ai/other")
      refute Redirect.matches?(registered, "http://claude.ai/api/mcp/auth_callback")
    end

    test "loopback ignores port only" do
      registered = ["http://localhost/callback", "http://127.0.0.1/callback"]
      assert Redirect.matches?(registered, "http://localhost:3118/callback")
      assert Redirect.matches?(registered, "http://127.0.0.1:49152/callback")
      assert Redirect.matches?(registered, "http://localhost/callback")
      refute Redirect.matches?(registered, "http://localhost:3118/other")
      refute Redirect.matches?(registered, "https://localhost:3118/callback")
      refute Redirect.matches?(registered, "http://localhost.evil.com:3118/callback")
    end
  end
end
