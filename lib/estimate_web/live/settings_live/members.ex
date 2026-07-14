defmodule EstimateWeb.SettingsLive.Members do
  use EstimateWeb, :live_view

  alias Estimate.Organizations
  alias EstimateWeb.SettingsLive.Members.{Invites, JoinRequests, TwoFactor, Roster, Removal}
  import EstimateWeb.SettingsLive.Components.MemberComponents
  import EstimateWeb.SettingsLive.Components.ReassignmentModal

  @valid_tabs ~w(members invites requests)
  @valid_reassign_tabs ~w(all per_customer per_project)

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
     |> Removal.reset_removal_state()}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @valid_tabs do
    {:noreply, assign(socket, :current_tab, String.to_existing_atom(tab))}
  end

  def handle_event("send_invite", params, socket), do: Invites.send_invite(socket, params)

  def handle_event("change_member_role", params, socket),
    do: Roster.change_member_role(socket, params)

  def handle_event("confirm_remove_member", params, socket),
    do: Removal.confirm_remove_member(socket, params)

  def handle_event("cancel_remove_member", params, socket),
    do: Removal.cancel_remove_member(socket, params)

  def handle_event("switch_reassign_tab", %{"tab" => tab}, socket)
      when tab in @valid_reassign_tabs,
      do: Removal.switch_reassign_tab(socket, tab)

  def handle_event("reassign_all", params, socket), do: Removal.reassign_all(socket, params)

  def handle_event("reassign_customer", params, socket),
    do: Removal.reassign_customer(socket, params)

  def handle_event("reassign_project", params, socket),
    do: Removal.reassign_project(socket, params)

  def handle_event("remove_member", params, socket), do: Removal.remove_member(socket, params)

  def handle_event("confirm_cancel_invite", params, socket),
    do: Invites.confirm_cancel_invite(socket, params)

  def handle_event("dismiss_cancel_invite", params, socket),
    do: Invites.dismiss_cancel_invite(socket, params)

  def handle_event("cancel_invite", params, socket), do: Invites.cancel_invite(socket, params)

  def handle_event("generate_invite_code", params, socket),
    do: Invites.generate_invite_code(socket, params)

  def handle_event("confirm_disable_2fa", params, socket),
    do: TwoFactor.confirm_disable_2fa(socket, params)

  def handle_event("cancel_disable_2fa", params, socket),
    do: TwoFactor.cancel_disable_2fa(socket, params)

  def handle_event("disable_user_2fa", params, socket),
    do: TwoFactor.disable_user_2fa(socket, params)

  def handle_event("copy_invite_code", params, socket),
    do: Invites.copy_invite_code(socket, params)

  def handle_event("dismiss_generated_code", params, socket),
    do: Invites.dismiss_generated_code(socket, params)

  def handle_event("copy_join_link", params, socket), do: Invites.copy_join_link(socket, params)

  def handle_event("copy_invite_link", params, socket),
    do: Invites.copy_invite_link(socket, params)

  def handle_event("approve_request", params, socket),
    do: JoinRequests.approve_request(socket, params)

  def handle_event("reject_request", params, socket),
    do: JoinRequests.reject_request(socket, params)

  # Catch-all for invalid tab values
  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}
  def handle_event("switch_reassign_tab", _params, socket), do: {:noreply, socket}
end
