defmodule EstimateWeb.EstimatorLive.Export do
  @moduledoc """
  Copy-as-JSON (clipboard push) and save-as-template.

  Reads: `:estimation`, `:show_all_in_rates`, `:enabled_priorities`, `:customer`, `:project`,
  `:org_id`, `:can_edit` (via Authz, template only).
  Writes: `:modal`, flash; pushes `copy_to_clipboard`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  import EstimateWeb.EstimatorLive.Helpers, only: [build_json_export: 4]
  alias Estimate.EstimationEngine.Calculator
  alias EstimateWeb.EstimatorLive.ViewState

  def copy_json(socket, _params) do
    estimation = socket.assigns.estimation
    dr = display_roles(estimation.roles, socket.assigns.show_all_in_rates)
    filtered = ViewState.filtered_epics(estimation, socket.assigns.enabled_priorities)

    json =
      build_json_export(
        %{estimation | epics: filtered},
        dr,
        socket.assigns.customer,
        socket.assigns.project
      )

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: json})
     |> put_flash(:info, "Copied!")}
  end

  def open_save_as_template(socket, _params) do
    with_edit_auth(socket, fn socket -> {:noreply, assign(socket, :modal, :save_template)} end)
  end

  def save_as_template(socket, %{"template_name" => name}) when name != "" do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation
      org_id = socket.assigns.org_id

      case Estimate.Templates.create_from_estimation(org_id, name, estimation) do
        {:ok, _template} ->
          {:noreply,
           socket
           |> assign(:modal, nil)
           |> put_flash(:info, "Template saved")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save template")}
      end
    end)
  end

  def save_as_template(socket, _params), do: {:noreply, socket}

  defp display_roles(roles, true), do: Calculator.roles_with_all_in_rates(roles)
  defp display_roles(roles, false), do: roles
end
