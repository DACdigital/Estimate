defmodule EstimateWeb.SettingsLive.Members do
  use EstimateWeb, :live_view

  alias Estimate.{Organizations, Portfolio}
  import EstimateWeb.LiveHelpers
  import EstimateWeb.SettingsLive.Components.MemberComponents
  import EstimateWeb.SettingsLive.Components.ReassignmentModal

  @valid_tabs ~w(members invites requests)
  @valid_reassign_tabs ~w(all per_customer per_project)
  @assignable_roles ~w(member admin)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Members</h1>
        <p class="mt-1 text-base-content/60">Manage team members and invitations</p>
      </div>

      <div :if={@is_admin} class="space-y-4 mb-8">
        <.invite_by_email_card invite_form={@invite_form} />
        <.invite_code_card generated_code={@generated_code} />
        <.join_link_card join_url={@join_url} />
      </div>

      <%!-- Tabs --%>
      <div class="border-b border-base-300 mb-6">
        <div class="flex gap-6">
          <button
            phx-click="switch_tab"
            phx-value-tab="members"
            class={[
              "pb-3 text-sm font-medium border-b-2 transition-colors",
              @current_tab == :members && "border-base-content text-base-content",
              @current_tab != :members &&
                "border-transparent text-base-content/60 hover:text-base-content/80"
            ]}
          >
            Team Members
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="invites"
            class={[
              "pb-3 text-sm font-medium border-b-2 transition-colors",
              @current_tab == :invites && "border-base-content text-base-content",
              @current_tab != :invites &&
                "border-transparent text-base-content/60 hover:text-base-content/80"
            ]}
          >
            Pending Invitations
            <span
              :if={@invites != []}
              class="ml-2 px-1.5 py-0.5 text-xs bg-base-200 text-base-content/70 rounded"
            >
              {length(@invites)}
            </span>
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="requests"
            class={[
              "pb-3 text-sm font-medium border-b-2 transition-colors",
              @current_tab == :requests && "border-base-content text-base-content",
              @current_tab != :requests &&
                "border-transparent text-base-content/60 hover:text-base-content/80"
            ]}
          >
            Join Requests
            <span
              :if={@join_requests != []}
              class="ml-2 px-1.5 py-0.5 text-xs bg-warning/10 text-warning rounded"
            >
              {length(@join_requests)}
            </span>
          </button>
        </div>
      </div>

      <.members_tab
        :if={@current_tab == :members}
        members={@members}
        current_user={@current_user}
        current_membership={@current_membership}
      />
      <.invitations_tab :if={@current_tab == :invites} invites={@invites} is_admin={@is_admin} />
      <.join_requests_tab
        :if={@current_tab == :requests}
        join_requests={@join_requests}
        is_admin={@is_admin}
      />
      <.confirm_modal
        :if={@removing_member && @sole_owned_projects == []}
        id="remove-member-modal"
        title="Remove Member"
        message={"Are you sure you want to remove #{@removing_member.user.name || @removing_member.user.email}? They will lose access to this organization."}
        confirm_text="Remove"
        confirm_event="remove_member"
        cancel_event="cancel_remove_member"
      />
      <.reassignment_modal
        :if={@removing_member && @sole_owned_projects != []}
        removing_member={@removing_member}
        sole_owned_projects={@sole_owned_projects}
        eligible_members={@eligible_members}
        reassign_tab={@reassign_tab}
        reassignments={@reassignments}
      />
      <.confirm_modal
        :if={@canceling_invite}
        id="cancel-invite-modal"
        title="Cancel Invitation"
        message={"Are you sure you want to cancel the invitation to #{@canceling_invite.email || @canceling_invite.code}?"}
        confirm_text="Cancel Invitation"
        cancel_text="Keep Invitation"
        confirm_event="cancel_invite"
        cancel_event="dismiss_cancel_invite"
      />
      <.confirm_modal
        :if={@disabling_2fa_user}
        id="disable-2fa-modal"
        title="Disable Two-Factor Authentication"
        message={"Are you sure you want to disable 2FA for #{@disabling_2fa_user.name || @disabling_2fa_user.email}? They will be able to log in without a second factor."}
        confirm_text="Disable 2FA"
        confirm_event="disable_user_2fa"
        cancel_event="cancel_disable_2fa"
      />
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org_id = socket.assigns.org_id
    is_admin = admin?(socket.assigns.current_membership)

    {:ok,
     socket
     |> assign(
       page_title: "Members",
       active_tab: :settings,
       settings_page: :members,
       current_tab: :members,
       members: Organizations.list_organization_members(org_id),
       invites: Organizations.list_organization_invites(org_id),
       join_requests: Organizations.list_pending_join_requests(org_id),
       canceling_invite: nil,
       disabling_2fa_user: nil,
       is_admin: is_admin,
       generated_code: nil,
       join_url: url(~p"/organizations/#{org_id}/join"),
       invite_form: to_form(%{"email" => "", "role" => "member"}, as: "invite")
     )
     |> reset_removal_state()}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @valid_tabs do
    {:noreply, assign(socket, :current_tab, String.to_existing_atom(tab))}
  end

  def handle_event("send_invite", %{"invite" => params}, socket) do
    require_admin(socket, fn ->
      user = socket.assigns.current_user
      org_id = socket.assigns.org_id

      case Organizations.create_invite(org_id, atomize_keys(params), user.id) do
        {:ok, invite} ->
          invites = Organizations.list_organization_invites(org_id)
          org = socket.assigns.current_organization

          flash =
            if Organizations.smtp_configured?(org) do
              email =
                Estimate.Emails.InviteEmail.invite_email(org, invite, user.name || user.email)

              case Estimate.Mailer.deliver_with_org_smtp(email, org) do
                {:ok, _} -> {:info, "Invitation sent via email!"}
                {:error, _} -> {:warning, "Invite created but email failed — copy link to share"}
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
    end)
  end

  def handle_event("change_member_role", %{"id" => id, "role" => role}, socket) do
    require_admin(socket, fn ->
      membership = Enum.find(socket.assigns.members, &(&1.id == id))

      cond do
        is_nil(membership) ->
          {:noreply, put_flash(socket, :error, "Member not found")}

        membership.role == "owner" or membership.user_id == socket.assigns.current_user.id ->
          {:noreply, put_flash(socket, :error, "Not authorized")}

        role not in @assignable_roles ->
          {:noreply, put_flash(socket, :error, "Invalid role")}

        true ->
          case Organizations.update_membership_role(membership, role) do
            {:ok, _} ->
              members = Organizations.list_organization_members(socket.assigns.org_id)
              {:noreply, socket |> put_flash(:info, "Role updated") |> assign(:members, members)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not update role")}
          end
      end
    end)
  end

  def handle_event("confirm_remove_member", %{"id" => id}, socket) do
    require_admin(socket, fn ->
      membership = Enum.find(socket.assigns.members, &(&1.id == id))

      if membership && membership.role != "owner" &&
           membership.user_id != socket.assigns.current_user.id do
        org_id = socket.assigns.org_id
        sole_owned = Portfolio.list_sole_owned_projects(membership.user_id, org_id)

        eligible =
          socket.assigns.members
          |> Enum.reject(&(&1.user_id == membership.user_id))
          |> Enum.sort_by(& &1.user.name)

        reassignments =
          case eligible do
            [first | _] -> Map.new(sole_owned, fn {p, _} -> {p.id, first.user_id} end)
            [] -> %{}
          end

        {:noreply,
         socket
         |> assign(
           removing_member: membership,
           sole_owned_projects: sole_owned,
           eligible_members: eligible,
           reassign_tab: :all,
           reassignments: reassignments
         )}
      else
        {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
  end

  def handle_event("cancel_remove_member", _params, socket) do
    {:noreply, reset_removal_state(socket)}
  end

  def handle_event("switch_reassign_tab", %{"tab" => tab}, socket)
      when tab in @valid_reassign_tabs do
    {:noreply, assign(socket, :reassign_tab, String.to_existing_atom(tab))}
  end

  def handle_event("reassign_all", %{"user_id" => user_id}, socket) do
    require_admin(socket, fn ->
      reassignments =
        if valid_eligible_member?(socket, user_id) do
          Map.new(socket.assigns.sole_owned_projects, fn {p, _} -> {p.id, user_id} end)
        else
          %{}
        end

      {:noreply, assign(socket, :reassignments, reassignments)}
    end)
  end

  def handle_event(
        "reassign_customer",
        %{"customer_id" => customer_id, "user_id" => user_id},
        socket
      ) do
    require_admin(socket, fn ->
      project_ids = sole_owned_project_ids_for_customer(socket, customer_id)

      reassignments =
        if valid_eligible_member?(socket, user_id) do
          Enum.reduce(project_ids, socket.assigns.reassignments, &Map.put(&2, &1, user_id))
        else
          Map.drop(socket.assigns.reassignments, project_ids)
        end

      {:noreply, assign(socket, :reassignments, reassignments)}
    end)
  end

  def handle_event(
        "reassign_project",
        %{"project_id" => project_id, "user_id" => user_id},
        socket
      ) do
    require_admin(socket, fn ->
      if valid_sole_owned_project?(socket, project_id) do
        reassignments =
          if valid_eligible_member?(socket, user_id),
            do: Map.put(socket.assigns.reassignments, project_id, user_id),
            else: Map.delete(socket.assigns.reassignments, project_id)

        {:noreply, assign(socket, :reassignments, reassignments)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("remove_member", _params, socket) do
    require_admin(socket, fn ->
      membership = socket.assigns.removing_member

      if membership && membership.role != "owner" &&
           membership.user_id != socket.assigns.current_user.id do
        case Organizations.delete_membership(membership, socket.assigns.reassignments) do
          {:ok, _} ->
            members = Organizations.list_organization_members(socket.assigns.org_id)

            {:noreply,
             socket
             |> put_flash(:info, "Member removed")
             |> assign(:members, members)
             |> reset_removal_state()}

          {:error, reason}
          when reason in [:invalid_project, :invalid_member, :self_reassignment] ->
            {:noreply,
             socket
             |> put_flash(:error, "Invalid reassignment")
             |> reset_removal_state()}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not remove member")
             |> reset_removal_state()}
        end
      else
        {:noreply,
         socket
         |> put_flash(:error, "Cannot remove this member")
         |> reset_removal_state()}
      end
    end)
  end

  def handle_event("confirm_cancel_invite", %{"id" => id}, socket) do
    invite = Enum.find(socket.assigns.invites, &(&1.id == id))
    {:noreply, assign(socket, :canceling_invite, invite)}
  end

  def handle_event("dismiss_cancel_invite", _params, socket) do
    {:noreply, assign(socket, :canceling_invite, nil)}
  end

  def handle_event("cancel_invite", _params, socket) do
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

  def handle_event("generate_invite_code", %{"role" => role}, socket) do
    require_admin(socket, fn ->
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
    end)
  end

  def handle_event("confirm_disable_2fa", %{"id" => user_id}, socket) do
    require_admin(socket, fn ->
      user = Estimate.Accounts.get_user!(user_id)
      {:noreply, assign(socket, :disabling_2fa_user, user)}
    end)
  end

  def handle_event("cancel_disable_2fa", _params, socket) do
    {:noreply, assign(socket, :disabling_2fa_user, nil)}
  end

  def handle_event("disable_user_2fa", _params, socket) do
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

  def handle_event("copy_invite_code", %{"code" => code}, socket) do
    require_admin(socket, fn ->
      {:noreply,
       socket
       |> push_event("copy_to_clipboard", %{text: code})
       |> put_flash(:info, "Code copied to clipboard!")}
    end)
  end

  def handle_event("dismiss_generated_code", _params, socket) do
    {:noreply, assign(socket, :generated_code, nil)}
  end

  def handle_event("copy_join_link", _params, socket) do
    require_admin(socket, fn ->
      {:noreply,
       socket
       |> push_event("copy_to_clipboard", %{text: socket.assigns.join_url})
       |> put_flash(:info, "Join link copied to clipboard!")}
    end)
  end

  def handle_event("copy_invite_link", %{"token" => token}, socket) do
    require_admin(socket, fn ->
      url = url(~p"/invites/#{token}")

      {:noreply,
       socket
       |> push_event("copy_to_clipboard", %{text: url})
       |> put_flash(:info, "Link copied to clipboard!")}
    end)
  end

  def handle_event("approve_request", %{"id" => id}, socket) do
    require_admin(socket, fn ->
      org_id = socket.assigns.org_id
      request = Organizations.get_join_request!(id, org_id)

      case Organizations.approve_join_request(request, socket.assigns.current_user.id) do
        {:ok, _} ->
          members = Organizations.list_organization_members(org_id)
          join_requests = Organizations.list_pending_join_requests(org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Request approved!")
           |> assign(:members, members)
           |> assign(:join_requests, join_requests)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not approve request")}
      end
    end)
  end

  def handle_event("reject_request", %{"id" => id}, socket) do
    require_admin(socket, fn ->
      org_id = socket.assigns.org_id
      request = Organizations.get_join_request!(id, org_id)

      case Organizations.reject_join_request(request, socket.assigns.current_user.id) do
        {:ok, _} ->
          join_requests = Organizations.list_pending_join_requests(org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Request rejected")
           |> assign(:join_requests, join_requests)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not reject request")}
      end
    end)
  end

  # Catch-all for invalid tab values
  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}
  def handle_event("switch_reassign_tab", _params, socket), do: {:noreply, socket}

  ## Helpers

  defp reset_removal_state(socket) do
    assign(socket,
      removing_member: nil,
      sole_owned_projects: [],
      eligible_members: [],
      reassign_tab: :all,
      reassignments: %{}
    )
  end

  defp valid_eligible_member?(socket, user_id) do
    user_id != "" and Enum.any?(socket.assigns.eligible_members, &(&1.user_id == user_id))
  end

  defp valid_sole_owned_project?(socket, project_id) do
    Enum.any?(socket.assigns.sole_owned_projects, fn {p, _} -> p.id == project_id end)
  end

  defp sole_owned_project_ids_for_customer(socket, customer_id) do
    socket.assigns.sole_owned_projects
    |> Enum.filter(fn {p, _} -> p.customer_id == customer_id end)
    |> Enum.map(fn {p, _} -> p.id end)
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
