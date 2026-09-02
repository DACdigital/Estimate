defmodule EstimateWeb.ClientIP do
  @moduledoc """
  Best-effort client address for rate limiting: first `x-forwarded-for` hop when the
  app sits behind a proxy, else the socket peer. Spoofable without a trusted proxy,
  which is why every IP bucket is paired with an identity bucket.
  """

  @spec get(Plug.Conn.t()) :: String.t()
  def get(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",", parts: 2) |> hd() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
