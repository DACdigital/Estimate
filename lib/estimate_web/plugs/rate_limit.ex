defmodule EstimateWeb.Plugs.RateLimit do
  @moduledoc "Per-client-IP fixed-window limit for JSON endpoints. `bucket:` selects the Estimate.RateLimit bucket."
  import Plug.Conn

  alias Estimate.RateLimit
  alias EstimateWeb.ClientIP

  def init(opts) do
    bucket = Keyword.fetch!(opts, :bucket)

    if bucket not in RateLimit.buckets() do
      raise ArgumentError,
            "unknown Estimate.RateLimit bucket #{inspect(bucket)}; " <>
              "expected one of #{inspect(RateLimit.buckets())}"
    end

    bucket
  end

  def call(conn, bucket) do
    case RateLimit.check(bucket, ClientIP.get(conn)) do
      {:allow, _} ->
        conn

      {:deny, retry_ms} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(RateLimit.retry_seconds(retry_ms)))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "too_many_requests"}))
        |> halt()
    end
  end
end
