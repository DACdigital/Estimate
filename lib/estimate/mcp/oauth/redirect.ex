defmodule Estimate.MCP.OAuth.Redirect do
  @moduledoc """
  OAuth redirect-URI rules: byte-exact matching, with the RFC 8252 loopback
  exception — registered `http://localhost/...` or `http://127.0.0.1/...`
  URIs match any port (Claude Code uses an ephemeral port per session).
  """

  @loopback_hosts ~w(localhost 127.0.0.1)

  def valid_for_registration?(uri_string) when is_binary(uri_string) do
    case URI.parse(uri_string) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      %URI{scheme: "http", host: host} when host in @loopback_hosts -> true
      _ -> false
    end
  end

  def valid_for_registration?(_), do: false

  def matches?(registered, presented) when is_list(registered) and is_binary(presented) do
    Enum.any?(registered, fn reg -> reg == presented or loopback_match?(reg, presented) end)
  end

  defp loopback_match?(registered, presented) do
    with %URI{scheme: "http", host: host, path: path} when host in @loopback_hosts <-
           URI.parse(registered),
         %URI{scheme: "http", host: ^host, path: ^path} <- URI.parse(presented) do
      true
    else
      _ -> false
    end
  end

  def loopback_only?(registered) when is_list(registered) do
    Enum.all?(registered, fn uri ->
      match?(%URI{scheme: "http", host: host} when host in @loopback_hosts, URI.parse(uri))
    end)
  end
end
