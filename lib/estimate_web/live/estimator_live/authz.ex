defmodule EstimateWeb.EstimatorLive.Authz do
  @moduledoc """
  Authorization gate and in-memory lookups shared by the EstimatorLive handler modules.

  Every mutating handler goes through `with_edit_auth/2`; every id coming from the
  client is resolved against the in-memory `@estimation` (never a bare
  `get_epic!/get_task!` by id) so a foreign id can never touch another estimation.

  Reads: `:can_edit`, `:estimation`, `:org_id`.
  Writes: `:estimation` (via `reload_estimation/1`), flash.
  """
  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 3]

  alias Estimate.EstimationEngine

  def with_edit_auth(socket, fun) when is_function(fun, 1) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, "You don't have edit access")}
    end
  end

  def not_found(socket), do: {:noreply, put_flash(socket, :error, "Not found")}

  def find_epic(%{epics: epics}, id), do: Enum.find(epics, &(&1.id == id))

  def find_task(%{epics: epics}, id),
    do: Enum.find_value(epics, fn epic -> Enum.find(epic.tasks, &(&1.id == id)) end)

  def belongs_to_estimation?(estimation, :task, id),
    do: Enum.any?(estimation.epics, fn ep -> Enum.any?(ep.tasks, &(&1.id == id)) end)

  def belongs_to_estimation?(estimation, :role, id),
    do: Enum.any?(estimation.roles, &(&1.id == id))

  def reload_estimation(socket) do
    estimation =
      EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

    assign(socket, :estimation, estimation)
  end
end
