defmodule EstimateWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Per-request Content Security Policy with a script nonce. Enforced by default;
  `config :estimate, EstimateWeb.Plugs.ContentSecurityPolicy, report_only: true`
  (env `CSP_REPORT_ONLY=true`) is a kill-switch for the full policy during a
  soak — NOT a telemetry/report-collection mode (there is no report endpoint
  configured). Soaks should be short: while report-only, the enforced header
  falls back to a strict baseline (`base-uri 'self'; frame-ancestors 'none'`),
  at least as strict as Phoenix's own default, while the full nonce policy
  ships report-only alongside it for comparison in the browser console/devtools.
  Any inline `<script>` must carry `nonce={@csp_nonce}`; external assets must be
  allow-listed here.

  Dev note: `/dev/mailbox` (the local mail preview, LiveDashboard-based) is
  nonce-aware, but any ad-hoc inline `<script>` added there without the nonce
  will be blocked by this policy same as in every other environment.
  """
  import Plug.Conn

  @enforced_baseline "base-uri 'self'; frame-ancestors 'none'"

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    conn = assign(conn, :csp_nonce, nonce)

    # `put_secure_browser_headers/1` (earlier in the :browser pipeline) already sets a
    # bare "content-security-policy" header — every branch below replaces or clears it
    # so a stale/default value never lingers.
    if report_only?() do
      conn
      |> put_resp_header("content-security-policy", @enforced_baseline)
      |> put_resp_header("content-security-policy-report-only", policy(nonce))
    else
      conn
      |> delete_resp_header("content-security-policy-report-only")
      |> put_resp_header("content-security-policy", policy(nonce))
    end
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

  @doc """
  Widens `form-action` on whichever CSP header(s) are already set on `conn` to
  also allow `origin`, for responses whose form POST redirects cross-origin
  (e.g. the OAuth consent page redirecting to the client's `redirect_uri`).
  Firefox enforces `form-action` across a form POST's redirect chain, so a
  bare `form-action 'self'` breaks that redirect.

  `origin` must come from a client's registered, already-validated redirect
  URI (see `Estimate.MCP.OAuth.Redirect.matches?/2`) — this widens the policy
  to a destination the request was already allowed to reach, adding no new
  trust.
  """
  @spec allow_form_action(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def allow_form_action(conn, origin) do
    conn
    |> widen_form_action("content-security-policy", origin)
    |> widen_form_action("content-security-policy-report-only", origin)
  end

  defp widen_form_action(conn, header, origin) do
    case get_resp_header(conn, header) do
      [value] ->
        put_resp_header(
          conn,
          header,
          String.replace(value, "form-action 'self'", "form-action 'self' #{origin}")
        )

      [] ->
        conn
    end
  end

  defp report_only?, do: Application.get_env(:estimate, __MODULE__, [])[:report_only] == true
end
