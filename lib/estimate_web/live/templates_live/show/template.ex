defmodule EstimateWeb.TemplatesLive.Show.Template do
  @moduledoc """
  Template header (inline name/description) and modal/delete housekeeping.

  Reads: `:template`, `:org_id`. Writes: `:template`, `:modal`, `:deleting_epic`, `:deleting_task`.
  """
  use EstimateWeb, :live_handlers

  alias Estimate.Templates

  def update_template(socket, params) do
    require_admin(socket, fn ->
      attrs = %{"name" => params["name"], "description" => params["description"]}

      case Templates.update_estimation_template(socket.assigns.template, attrs) do
        {:ok, template} ->
          template = Templates.get_estimation_template!(template.id, socket.assigns.org_id)
          {:noreply, assign(socket, :template, template)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save template")}
      end
    end)
  end

  def close_modal(socket, _params), do: {:noreply, assign(socket, :modal, nil)}

  def cancel_delete(socket, _params),
    do: {:noreply, socket |> assign(:deleting_epic, nil) |> assign(:deleting_task, nil)}
end
