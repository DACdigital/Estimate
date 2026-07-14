defmodule EstimateWeb.SettingsLive.Members.TwoFactor do
  @moduledoc "Event handlers for admin-initiated 2FA disable on a member."
  use EstimateWeb, :live_handlers

  alias Estimate.Organizations

  def confirm_disable_2fa(socket, %{"id" => user_id}) do
    require_admin(socket, fn ->
      if Organizations.get_user_membership(user_id, socket.assigns.org_id) do
        user = Estimate.Accounts.get_user!(user_id)
        {:noreply, assign(socket, :disabling_2fa_user, user)}
      else
        {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
  end

  def cancel_disable_2fa(socket, _params),
    do: {:noreply, assign(socket, :disabling_2fa_user, nil)}

  def disable_user_2fa(socket, _params) do
    require_admin(socket, fn ->
      user = socket.assigns.disabling_2fa_user

      if user do
        case Estimate.Accounts.Totp.disable_totp(user) do
          {:ok, _} ->
            members = Organizations.list_organization_members(socket.assigns.org_id)

            {:noreply,
             socket
             |> put_flash(:info, "2FA disabled for #{user.name || user.email}")
             |> assign(:members, members)
             |> assign(:disabling_2fa_user, nil)}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not disable 2FA")
             |> assign(:disabling_2fa_user, nil)}
        end
      else
        {:noreply, assign(socket, :disabling_2fa_user, nil)}
      end
    end)
  end
end
