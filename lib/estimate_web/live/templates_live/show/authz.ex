defmodule EstimateWeb.TemplatesLive.Show.Authz do
  @moduledoc """
  Lookups and reload helpers shared by the TemplatesLive.Show handler modules.
  Admin gating itself is `EstimateWeb.AuthHelpers.require_admin/2` (via `:live_handlers`).

  Reads: `:template`, `:org_id`. Writes: `:template` (reload), `:modal` (reload_and_close), flash.

  `find_*` return `nil` for unknown ids; handlers flash `not_found/1`.

  Every id coming from the client is resolved against the in-memory `@template` (never a bare
  `Repo.get`/`get_*!` by id), so a foreign id can never touch another template.
  """
  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 3]

  alias Estimate.Templates

  def find_epic(template, id), do: Enum.find(template.epics, &(&1.id == id))

  def find_task(template, epic_id, task_id) do
    case find_epic(template, epic_id) do
      nil -> nil
      epic -> Enum.find(epic.tasks, &(&1.id == task_id))
    end
  end

  def not_found(socket), do: {:noreply, put_flash(socket, :error, "Not found")}

  def reload_template(socket) do
    template =
      Templates.get_estimation_template!(socket.assigns.template.id, socket.assigns.org_id)

    assign(socket, :template, template)
  end

  def reload_and_close(socket), do: socket |> reload_template() |> assign(:modal, nil)

  def after_reorder(:ok, socket), do: {:noreply, reload_template(socket)}

  def after_reorder({:error, :stale_reorder}, socket),
    do:
      {:noreply,
       socket |> reload_template() |> put_flash(:error, "Order changed elsewhere; reloaded")}
end
