defmodule EstimateWeb.AuthHelpers do
  @moduledoc false

  alias Estimate.Accounts.Membership

  def admin?(%{role: role}), do: role in Membership.admin_roles()
  def admin?(_), do: false
end
