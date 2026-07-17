defmodule Estimate.MCP.OAuth.PKCE do
  @moduledoc "PKCE S256 (RFC 7636). Only S256 is supported — `plain` is rejected upstream."

  @charset ~r/^[A-Za-z0-9._~-]{43,128}$/

  def valid_challenge?(challenge) when is_binary(challenge), do: Regex.match?(@charset, challenge)
  def valid_challenge?(_), do: false

  def verify(challenge, verifier) when is_binary(challenge) and is_binary(verifier) do
    computed = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    byte_size(challenge) == byte_size(computed) and
      Plug.Crypto.secure_compare(challenge, computed)
  end

  def verify(_, _), do: false
end
