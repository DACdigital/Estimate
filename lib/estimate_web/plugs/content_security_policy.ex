defmodule EstimateWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Per-request Content Security Policy with a script nonce. Enforced by default;
  `config :estimate, EstimateWeb.Plugs.ContentSecurityPolicy, report_only: true`
  (env `CSP_REPORT_ONLY=true`) switches to the report-only header for a soak.
  Any inline `<script>` must carry `nonce={@csp_nonce}`; external assets must be
  allow-listed here.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    header =
      if report_only?(),
        do: "content-security-policy-report-only",
        else: "content-security-policy"

    other_header =
      if header == "content-security-policy",
        do: "content-security-policy-report-only",
        else: "content-security-policy"

    conn
    |> assign(:csp_nonce, nonce)
    # `put_secure_browser_headers/1` (earlier in the :browser pipeline) already sets a
    # bare "content-security-policy" header — clear whichever header we're not using so
    # a stale/default value never lingers alongside ours.
    |> delete_resp_header(other_header)
    |> put_resp_header(header, policy(nonce))
  end

  @spec policy(String.t()) :: String.t()
  def policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src 'self' https://fonts.gstatic.com data:",
        "img-src 'self' data: blob:",
        "connect-src 'self' ws: wss:",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'"
      ],
      "; "
    )
  end

  defp report_only?, do: Application.get_env(:estimate, __MODULE__, [])[:report_only] == true
end
