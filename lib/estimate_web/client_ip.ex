defmodule EstimateWeb.ClientIP do
  @moduledoc """
  Best-effort client address for rate limiting.

  `config :estimate, EstimateWeb.ClientIP, trusted_proxy_hops: N` controls how the
  `x-forwarded-for` header is trusted:

    * `N == 0` — the header is ignored entirely; the socket peer (`conn.remote_ip`) is
      always used. Required when the app is exposed directly to the internet (no
      reverse proxy in front of it) — otherwise a client can set `x-forwarded-for`
      itself and forge any address it likes.
    * `N >= 1` — the N-th entry counted from the *end* of the comma-separated
      `x-forwarded-for` list is used. Each hop between the client and this app
      appends its own address to the header, so the last entry is whatever the
      nearest trusted proxy appended (the only part of the header a client cannot
      forge); `N = 1` selects that entry, `N = 2` the one before it, and so on for
      chained proxies. If the header has fewer than `N` entries, or is absent, this
      falls back to `conn.remote_ip`.

  The documented deployment (a single k8s ingress hop) uses `N = 1`
  (`TRUSTED_PROXY_HOPS`, default `1`).

  Spoofable without a correctly configured trusted-proxy count, which is why every
  IP-scoped rate-limit bucket that matters is paired with an identity bucket: the
  login throttle checks `:login_ip` alongside `:login_email`, so a forged IP alone
  cannot bypass the per-email limit. The OAuth registration/token endpoints have no
  identity to pair with and rely on the `:oauth_ip` bucket alone — correct
  `TRUSTED_PROXY_HOPS` configuration matters most for them.
  """

  @spec get(Plug.Conn.t()) :: String.t()
  def get(%Plug.Conn{} = conn) do
    case trusted_hop(conn, trusted_proxy_hops()) do
      {:ok, ip} -> ip
      :error -> remote_ip(conn)
    end
  end

  defp trusted_hop(_conn, hops) when hops <= 0, do: :error

  defp trusted_hop(conn, hops) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [header | _] ->
        entries = header |> String.split(",") |> Enum.map(&String.trim/1)

        if length(entries) >= hops do
          {:ok, Enum.at(entries, -hops)}
        else
          :error
        end

      [] ->
        :error
    end
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp trusted_proxy_hops do
    :estimate
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:trusted_proxy_hops, 1)
  end
end
