defmodule EstimateWeb.EstimatorLive.Settings do
  @moduledoc """
  Estimation settings modal: name/currency, role rows (rates + overheads),
  add/delete/reorder roles.

  Reads: `:estimation`, `:org_id`, `:deleting_role_id`, `:can_edit` (via Authz).
  Writes: `:modal`, `:deleting_role_id`, `:estimation` (reload), flash.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  import EstimateWeb.EstimatorLive.Helpers, only: [parse_decimal: 1]
  alias Estimate.EstimationEngine
  alias Estimate.Repo

  def open_settings(socket, _params) do
    with_edit_auth(socket, fn socket -> {:noreply, assign(socket, :modal, :settings)} end)
  end

  def add_estimation_role(socket, %{"new_role_name" => name, "new_role_abbr" => abbr})
      when name != "" and abbr != "" do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation

      attrs = %{
        name: name,
        abbreviation: String.upcase(abbr),
        estimation_id: estimation.id,
        position: length(estimation.roles),
        hourly_rate: Decimal.new(0),
        pm_overhead: Decimal.new(0),
        qa_overhead: Decimal.new(0),
        risk_buffer: Decimal.new(0)
      }

      case EstimationEngine.create_role(attrs) do
        {:ok, _role} ->
          {:noreply, reload_estimation(socket) |> put_flash(:info, "Role added")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add role")}
      end
    end)
  end

  def add_estimation_role(socket, _params), do: {:noreply, socket}

  def save_settings(socket, params) do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation

      attrs = %{
        "name" => params["name"],
        "currency_id" => params["currency_id"]
      }

      roles_params = params["roles"] || %{}

      roles_result =
        Repo.each_ok(roles_params, fn {role_id, role_attrs} ->
          case Enum.find(estimation.roles, &(&1.id == role_id)) do
            nil ->
              {:error, :unauthorized_role}

            role ->
              case EstimationEngine.update_role(role, %{
                     name: role_attrs["name"] || role.name,
                     abbreviation: role_attrs["abbreviation"] || role.abbreviation,
                     hourly_rate: parse_decimal(role_attrs["hourly_rate"]),
                     pm_overhead: parse_decimal(role_attrs["pm_overhead"]),
                     qa_overhead: parse_decimal(role_attrs["qa_overhead"]),
                     risk_buffer: parse_decimal(role_attrs["risk_buffer"])
                   }) do
                {:ok, _} -> :ok
                {:error, _} -> {:error, :role_update_failed}
              end
          end
        end)

      case roles_result do
        {:error, _reason} ->
          # Some roles may have been updated before the loop halted (writes
          # already landed); reload so the originator's memory matches the DB.
          {:noreply, socket |> reload_estimation() |> put_flash(:error, "Could not update roles")}

        :ok ->
          case EstimationEngine.update_estimation(estimation, attrs) do
            {:ok, _} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> put_flash(:info, "Settings saved")}

            {:error, _changeset} ->
              # Role updates in this call already succeeded and landed in the
              # DB even though the estimation-level change failed; reload so
              # the originator doesn't show stale rates (broadcast_from means
              # this LV never hears its own writes).
              {:noreply,
               socket |> reload_estimation() |> put_flash(:error, "Could not save settings")}
          end
      end
    end)
  end

  def confirm_delete_role(socket, %{"id" => role_id}) do
    with_edit_auth(socket, fn socket -> {:noreply, assign(socket, :deleting_role_id, role_id)} end)
  end

  def cancel_delete_role(socket, _params), do: {:noreply, assign(socket, :deleting_role_id, nil)}

  def delete_estimation_role(socket, _params) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_role_id do
        nil ->
          {:noreply, socket}

        role_id ->
          case Enum.find(socket.assigns.estimation.roles, &(&1.id == role_id)) do
            nil ->
              {:noreply, put_flash(socket, :error, "Not authorized")}

            role ->
              EstimationEngine.delete_role(role)

              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:deleting_role_id, nil)
               |> put_flash(:info, "Role deleted")}
          end
      end
    end)
  end

  def reorder_roles(socket, %{"ids" => ids}) do
    with_edit_auth(socket, fn socket ->
      EstimationEngine.reorder_roles(socket.assigns.estimation.id, ids)
      {:noreply, reload_estimation(socket)}
    end)
  end
end
