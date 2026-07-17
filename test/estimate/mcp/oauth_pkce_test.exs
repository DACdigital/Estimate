defmodule Estimate.MCP.OAuth.PKCETest do
  use ExUnit.Case, async: true

  alias Estimate.MCP.OAuth.PKCE

  @rfc_verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  @rfc_challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

  test "verifies the RFC 7636 appendix B vector" do
    assert PKCE.verify(@rfc_challenge, @rfc_verifier)
  end

  test "rejects wrong verifier and malformed input" do
    refute PKCE.verify(@rfc_challenge, "wrong-verifier-wrong-verifier-wrong-verifier")
    refute PKCE.verify("", @rfc_verifier)
    refute PKCE.verify(nil, @rfc_verifier)
    refute PKCE.verify(@rfc_challenge, nil)
  end

  test "valid_challenge? enforces charset and length" do
    assert PKCE.valid_challenge?(@rfc_challenge)
    refute PKCE.valid_challenge?("short")
    refute PKCE.valid_challenge?(String.duplicate("a", 129))
    refute PKCE.valid_challenge?(String.duplicate("a", 42) <> "!")
    refute PKCE.valid_challenge?(nil)
  end

  test "valid_challenge? rejects trailing newline (regression: anchors)" do
    # Old regex ~r/^...$/ matches before trailing \n; new \A...\z rejects it
    refute PKCE.valid_challenge?(String.duplicate("a", 128) <> "\n")
    refute PKCE.valid_challenge?(String.duplicate("a", 43) <> "\n")
  end
end
