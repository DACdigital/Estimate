defmodule EstimateWeb.HealthController do
  use EstimateWeb, :controller

  def liveness(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{status: "ok", revision: Estimate.BuildInfo.git_sha() || "unknown"})
  end

  def readiness(conn, _params) do
    case Ecto.Adapters.SQL.query(Estimate.Repo, "SELECT 1", [], timeout: 2_000) do
      {:ok, _} ->
        conn
        |> put_status(200)
        |> json(%{status: "ok", checks: %{database: "ok"}})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", checks: %{database: "error"}})
    end
  end
end
