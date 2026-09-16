defmodule EstimateWeb.AuthHelpers do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Estimate.Accounts.Membership
  alias Estimate.Portfolio.ProjectCollaborator

  def admin?(%{role: role}), do: role in Membership.admin_roles()
  def admin?(_), do: false

  @doc "True when the membership is org admin/owner or the collaborator row has an editing role."
  def can_edit_project?(membership, collaborator) do
    admin?(membership) or
      (collaborator != nil and collaborator.role in ProjectCollaborator.edit_roles())
  end

  def require_admin(socket, fun) do
    if admin?(socket.assigns.current_membership),
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "Not authorized")}
  end
end
