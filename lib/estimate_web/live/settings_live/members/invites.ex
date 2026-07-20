defmodule EstimateWeb.SettingsLive.Members.Invites do
  @moduledoc "Event handlers for the members invitations panel (email/code/links/cancel)."
  use EstimateWeb, :live_handlers

  alias Estimate.Organizations
  alias Estimate.Accounts.Membership

  def send_invite(socket, %{"invite" => params}) do
    require_admin(socket, fn ->
      user = socket.assigns.current_user
      org_id = socket.assigns.org_id

      if params["role"] not in Membership.assignable_roles() do
        {:noreply, put_flash(socket, :error, "Invalid role")}
      else
        case Organizations.create_invite(org_id, atomize_keys(params), user.id) do
          {:ok, invite} ->
            invites = Organizations.list_organization_invites(org_id)
            org = socket.assigns.current_organization

            flash =
              if Organizations.smtp_configured?(org) do
                email =
                  Estimate.Emails.InviteEmail.invite_email(org, invite, user.name || user.email)

                case Estimate.Mailer.deliver_with_org_smtp(email, org) do
                  {:ok, _} ->
                    {:info, "Invitation sent via email!"}

                  {:error, _} ->
                    {:warning, "Invite created but email failed — copy link to share"}
                end
              else
                {:info, "Invite created — copy link to share"}
              end

            {:noreply,
             socket
             |> put_flash(elem(flash, 0), elem(flash, 1))
             |> assign(:invites, invites)
             |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: "invite"))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not create invitation")}
        end
      end
    end)
  end

  def generate_invite_code(socket, %{"role" => role}) do
    require_admin(socket, fn ->
      if role not in Membership.assignable_roles() do
        {:noreply, put_flash(socket, :error, "Invalid role")}
      else
        user = socket.assigns.current_user
        org_id = socket.assigns.org_id

        case Organizations.create_invite_code(org_id, role, user.id) do
          {:ok, invite} ->
            invites = Organizations.list_organization_invites(org_id)

            {:noreply,
             socket
             |> assign(:generated_code, invite.code)
             |> assign(:invites, invites)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not generate invite code")}
        end
      end
    end)
  end

  def copy_invite_code(socket, %{"code" => code}) do
    require_admin(socket, fn ->
      copy_to_clipboard(socket, known_invite_code(socket, code), "Code copied to clipboard!")
    end)
  end

  def dismiss_generated_code(socket, _params),
    do: {:noreply, assign(socket, :generated_code, nil)}

  def copy_join_link(socket, _params) do
    require_admin(socket, fn ->
      copy_to_clipboard(socket, socket.assigns.join_url, "Join link copied to clipboard!")
    end)
  end

  def copy_invite_link(socket, %{"token" => token}) do
    require_admin(socket, fn ->
      copy_to_clipboard(socket, known_invite_link(socket, token), "Link copied to clipboard!")
    end)
  end

  def confirm_cancel_invite(socket, %{"id" => id}) do
    invite = Enum.find(socket.assigns.invites, &(&1.id == id))
    {:noreply, assign(socket, :canceling_invite, invite)}
  end

  def dismiss_cancel_invite(socket, _params),
    do: {:noreply, assign(socket, :canceling_invite, nil)}

  def cancel_invite(socket, _params) do
    require_admin(socket, fn ->
      invite = socket.assigns.canceling_invite

      if invite do
        Organizations.delete_invite(invite)
        invites = Organizations.list_organization_invites(socket.assigns.org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Invitation cancelled")
         |> assign(:invites, invites)
         |> assign(:canceling_invite, nil)}
      else
        {:noreply, assign(socket, :canceling_invite, nil)}
      end
    end)
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  # Copy payloads are recomputed from server state — the client only names which
  # invite; a value not backed by a visible invite yields nil and a silent
  # no-op, so a forged param can never be echoed back to the clipboard.
  # secure_compare avoids leaking, via timing, which codes/tokens exist.
  defp known_invite_code(socket, code) when is_binary(code) do
    Enum.find_value(socket.assigns.invites, fn invite ->
      if is_binary(invite.code) and Plug.Crypto.secure_compare(invite.code, code),
        do: invite.code
    end)
  end

  defp known_invite_code(_socket, _code), do: nil

  defp known_invite_link(socket, token) when is_binary(token) do
    Enum.find_value(socket.assigns.invites, fn invite ->
      if is_binary(invite.token) and Plug.Crypto.secure_compare(invite.token, token),
        do: url(~p"/invites/#{invite.token}")
    end)
  end

  defp known_invite_link(_socket, _token), do: nil

  defp copy_to_clipboard(socket, nil, _flash), do: {:noreply, socket}

  defp copy_to_clipboard(socket, text, flash) do
    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: text})
     |> put_flash(:info, flash)}
  end
end
