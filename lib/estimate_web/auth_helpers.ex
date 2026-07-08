defmodule EstimateWeb.AuthHelpers do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Estimate.Accounts.Membership

  def admin?(%{role: role}), do: role in Membership.admin_roles()
  def admin?(_), do: false

  def require_admin(socket, fun) do
    if admin?(socket.assigns.current_membership),
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "Not authorized")}
  end
end
