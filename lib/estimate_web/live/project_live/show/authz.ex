defmodule EstimateWeb.ProjectLive.Show.Authz do
  @moduledoc "Authorization + estimation-fetch helpers for ProjectLive.Show handler modules."
  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 2]
  alias Estimate.EstimationEngine

  # Each require_can_* runs `fun` iff the matching `can_*` assign is true, else flashes
  # "Not authorized". The arity-3 form additionally applies `deny_assigns` on the denial
  # path — preserving the assign reset (e.g. `deleting_project: false`) that a handler's
  # old compound outer gate performed on its unauthorized else-branch.
  def require_can_edit(socket, fun), do: require_can_edit(socket, [], fun)

  def require_can_edit(socket, deny_assigns, fun),
    do: gate(socket.assigns.can_edit_project, socket, deny_assigns, fun)

  def require_can_delete(socket, fun), do: require_can_delete(socket, [], fun)

  def require_can_delete(socket, deny_assigns, fun),
    do: gate(socket.assigns.can_delete_project, socket, deny_assigns, fun)

  def require_can_manage(socket, fun), do: require_can_manage(socket, [], fun)

  def require_can_manage(socket, deny_assigns, fun),
    do: gate(socket.assigns.can_manage_collaborators, socket, deny_assigns, fun)

  defp gate(true, _socket, _deny_assigns, fun), do: fun.()

  defp gate(_other, socket, deny_assigns, _fun),
    do: {:noreply, socket |> assign(deny_assigns) |> put_flash(:error, "Not authorized")}

  @doc "Fetch an estimation by id (rescuing a cross-org NoResultsError) and verify it belongs to the current project."
  def fetch_authorized_estimation(socket, id) do
    est = EstimationEngine.get_estimation!(id, socket.assigns.org_id)

    if est.project_id == socket.assigns.project.id,
      do: {:ok, est},
      else: {:error, :wrong_project}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def find_deleted_estimation(socket, id) do
    case Enum.find(socket.assigns.deleted_estimations, &(&1.id == id)) do
      nil -> :error
      est -> {:ok, est}
    end
  end
end
