defmodule EstimateWeb.AuthHelpers do
  @moduledoc false

  def admin?(%{role: role}), do: role in ["owner", "admin"]
  def admin?(_), do: false
end
