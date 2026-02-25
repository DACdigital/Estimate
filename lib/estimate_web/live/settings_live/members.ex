defmodule EstimateWeb.SettingsLive.Members do
  use EstimateWeb, :live_view

  alias Estimate.{Organizations, Portfolio}
  import EstimateWeb.LiveHelpers

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

      <.invite_by_email_card :if={@is_admin} invite_form={@invite_form} />
      <.invite_code_card :if={@is_admin} generated_code={@generated_code} />
      <.join_link_card :if={@is_admin} join_url={@join_url} />

      <%!-- Tabs --%>
      <div class="border-b border-base-300 mb-6">
        <div class="flex gap-6">
          <button
            phx-click="switch_tab"
            phx-value-tab="members"
            class={[
              "pb-3 text-sm font-medium border-b-2 transition-colors",
              @current_tab == :members && "border-base-content text-base-content",
              @current_tab != :members && "border-transparent text-base-content/60 hover:text-base-content/80"
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
              @current_tab != :invites && "border-transparent text-base-content/60 hover:text-base-content/80"
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
              @current_tab != :requests && "border-transparent text-base-content/60 hover:text-base-content/80"
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
      <.join_requests_tab :if={@current_tab == :requests} join_requests={@join_requests} is_admin={@is_admin} />
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
    </div>
    """
  end

  defp invite_by_email_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden mb-4">
      <div class="p-6">
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-base-content/70">Invite new members by email address</p>
        </div>

        <.form for={@invite_form} id="invite-form" phx-submit="send_invite" class="flex gap-4">
          <div class="flex-1">
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">Email Address</label>
            <input
              type="email"
              name={@invite_form[:email].name}
              value={@invite_form[:email].value}
              placeholder="jane@example.com"
              required
              class="w-full px-3 py-2 bg-base-200 border border-base-300 rounded-lg text-sm"
            />
          </div>
          <div class="w-48">
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">Role</label>
            <select
              name={@invite_form[:role].name}
              class="w-full px-3 py-2 bg-base-200 border border-base-300 rounded-lg text-sm"
            >
              <option value="member" selected={@invite_form[:role].value == "member"}>
                Member
              </option>
              <option value="admin" selected={@invite_form[:role].value == "admin"}>Admin</option>
            </select>
          </div>
          <div class="flex items-end">
            <button
              type="submit"
              phx-disable-with="Sending..."
              class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
            >
              Invite
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp invite_code_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden mb-8">
      <div class="p-6">
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-base-content/70">
            Generate a short invite code to share verbally or via text
          </p>
        </div>

        <%= if @generated_code do %>
          <div class="flex items-center gap-4">
            <div class="flex-1 flex items-center justify-center py-3 bg-base-200 border border-base-300 rounded-lg">
              <span class="font-mono text-2xl tracking-widest text-base-content select-all">
                {@generated_code}
              </span>
            </div>
            <button
              phx-click="copy_invite_code"
              phx-value-code={@generated_code}
              class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
            >
              Copy
            </button>
            <button
              phx-click="dismiss_generated_code"
              class="px-4 py-2 text-sm text-base-content/60 hover:text-base-content transition-colors"
            >
              Done
            </button>
          </div>
        <% else %>
          <form phx-submit="generate_invite_code" class="flex gap-4">
            <div class="w-48">
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Role</label>
              <select
                name="role"
                class="w-full px-3 py-2 bg-base-200 border border-base-300 rounded-lg text-sm"
              >
                <option value="member">Member</option>
                <option value="admin">Admin</option>
              </select>
            </div>
            <div class="flex items-end">
              <button
                type="submit"
                phx-disable-with="Generating..."
                class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
              >
                Generate Code
              </button>
            </div>
          </form>
        <% end %>
      </div>
    </div>
    """
  end

  defp join_link_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden mb-8">
      <div class="p-6">
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-base-content/70">
            Share this link to let people request to join your organization
          </p>
        </div>
        <div class="flex items-center gap-4">
          <div class="flex-1 px-3 py-2 bg-base-200 border border-base-300 rounded-lg text-sm text-base-content/70 truncate font-mono">
            {@join_url}
          </div>
          <button
            phx-click="copy_join_link"
            class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            Copy Link
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp members_tab(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
      <div
        :for={membership <- Enum.sort_by(@members, &(&1.user_id != @current_user.id))}
        class="px-6 py-4 flex items-center justify-between border-b border-base-content/10 last:border-b-0"
      >
        <div class="flex items-center gap-3">
          <.avatar name={membership.user.name || membership.user.email} seed={membership.user.id} />
          <div>
            <div class="flex items-center gap-2">
              <h3 class="text-sm font-medium text-base-content">{membership.user.name}</h3>
              <span
                :if={membership.user_id == @current_user.id}
                class="text-[10px] px-1.5 py-0.5 bg-base-200 text-base-content/60 rounded-full font-medium"
              >
                You
              </span>
            </div>
            <p class="text-sm text-base-content/60">{membership.user.email}</p>
          </div>
        </div>
        <div class="flex items-center gap-4">
          <%= if admin?(@current_membership) && membership.role != "owner" && membership.user_id != @current_user.id do %>
            <form phx-change="change_member_role" phx-value-id={membership.id}>
              <select
                name="role"
                class="text-sm px-2 py-1 border border-base-300 rounded-lg"
              >
                <option value="member" selected={membership.role == "member"}>Member</option>
                <option value="admin" selected={membership.role == "admin"}>Admin</option>
              </select>
            </form>
            <button
              phx-click="confirm_remove_member"
              phx-value-id={membership.id}
              class="text-base-content/40 hover:text-error transition-colors"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          <% else %>
            <span class="text-sm text-base-content/60 capitalize">{membership.role}</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp invitations_tab(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
      <%= if @invites == [] do %>
        <div class="px-6 py-12 text-center">
          <p class="text-sm text-base-content/60">No pending invitations</p>
        </div>
      <% else %>
        <div
          :for={invite <- @invites}
          class="px-6 py-4 flex items-center justify-between border-b border-base-content/10 last:border-b-0"
        >
          <div class="flex items-center gap-3">
            <%= if invite.code && !invite.email do %>
              <div class="w-10 h-10 rounded-full bg-base-200 flex items-center justify-center text-base-content/40">
                <.icon name="hero-key" class="w-5 h-5" />
              </div>
              <div>
                <div class="flex items-center gap-2">
                  <span class="font-mono text-sm font-medium text-base-content tracking-wider">
                    {invite.code}
                  </span>
                  <span class="px-1.5 py-0.5 text-xs bg-base-200 text-base-content/60 rounded">
                    code
                  </span>
                </div>
                <p class="text-sm text-base-content/60">
                  Expires {Calendar.strftime(invite.expires_at, "%b %d, %Y")}
                </p>
              </div>
            <% else %>
              <div class="w-10 h-10 rounded-full bg-base-200 flex items-center justify-center text-base-content/40">
                <.icon name="hero-envelope" class="w-5 h-5" />
              </div>
              <div>
                <h3 class="text-sm font-medium text-base-content">{invite.email}</h3>
                <p class="text-sm text-base-content/60">
                  Expires {Calendar.strftime(invite.expires_at, "%b %d, %Y")}
                </p>
              </div>
            <% end %>
          </div>
          <div class="flex items-center gap-4">
            <span class="text-sm text-base-content/60 capitalize">{invite.role}</span>
            <div :if={@is_admin} class="flex items-center gap-2">
              <%= if invite.code && !invite.email do %>
                <button
                  phx-click="copy_invite_code"
                  phx-value-code={invite.code}
                  class="text-sm text-base-content/60 hover:text-base-content transition-colors"
                >
                  Copy Code
                </button>
              <% else %>
                <button
                  phx-click="copy_invite_link"
                  phx-value-token={invite.token}
                  class="text-sm text-base-content/60 hover:text-base-content transition-colors"
                >
                  Copy Link
                </button>
              <% end %>
              <button
                phx-click="confirm_cancel_invite"
                phx-value-id={invite.id}
                class="text-sm text-base-content/60 hover:text-error transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp join_requests_tab(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
      <%= if @join_requests == [] do %>
        <div class="px-6 py-12 text-center">
          <p class="text-sm text-base-content/60">No pending join requests</p>
        </div>
      <% else %>
        <div
          :for={request <- @join_requests}
          class="px-6 py-4 flex items-center justify-between border-b border-base-content/10 last:border-b-0"
        >
          <div class="flex items-center gap-3">
            <.avatar name={request.user.name || request.user.email} seed={request.user.id} type={:pending} />
            <div>
              <h3 class="text-sm font-medium text-base-content">{request.user.name}</h3>
              <p class="text-sm text-base-content/60">{request.user.email}</p>
              <p class="text-xs text-base-content/40">
                Requested {Calendar.strftime(request.inserted_at, "%b %d, %Y")}
              </p>
            </div>
          </div>
          <div :if={@is_admin} class="flex items-center gap-2">
            <button
              phx-click="approve_request"
              phx-value-id={request.id}
              class="px-3 py-1.5 text-sm font-medium text-success bg-success/10 rounded-lg hover:bg-success/20 transition-colors"
            >
              Approve
            </button>
            <button
              phx-click="reject_request"
              phx-value-id={request.id}
              class="px-3 py-1.5 text-sm font-medium text-error bg-error/10 rounded-lg hover:bg-error/20 transition-colors"
            >
              Reject
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp reassignment_modal(assigns) do
    member_name = assigns.removing_member.user.name || assigns.removing_member.user.email
    project_count = length(assigns.sole_owned_projects)
    all_assigned? = reassignments_complete?(assigns)

    assigns =
      assigns
      |> assign(:member_name, member_name)
      |> assign(:project_count, project_count)
      |> assign(:all_assigned?, all_assigned?)

    ~H"""
    <.modal id="reassign-modal" show on_cancel={JS.push("cancel_remove_member")}>
      <div>
        <div class="flex items-center gap-3 mb-4">
          <div class="w-10 h-10 rounded-full bg-warning/10 flex items-center justify-center">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-warning" />
          </div>
          <div>
            <h3 class="text-lg font-semibold text-base-content">Remove Member</h3>
            <p class="text-sm text-base-content/60">
              {@member_name} is the sole owner of {@project_count}
              {ngettext("project", "projects", @project_count)}. Reassign ownership before removing.
            </p>
          </div>
        </div>

        <%!-- Tabs --%>
        <div class="border-b border-base-300 mb-4">
          <div class="flex gap-4">
            <button
              :for={
                {tab, label} <- [
                  {:all, "All"},
                  {:per_customer, "Per customer"},
                  {:per_project, "Per project"}
                ]
              }
              phx-click="switch_reassign_tab"
              phx-value-tab={tab}
              class={[
                "pb-2 text-sm font-medium border-b-2 transition-colors",
                @reassign_tab == tab && "border-base-content text-base-content",
                @reassign_tab != tab &&
                  "border-transparent text-base-content/60 hover:text-base-content/80"
              ]}
            >
              {label}
            </button>
          </div>
        </div>

        <%!-- Tab content --%>
        <div class="max-h-80 overflow-y-auto">
          <.reassign_all_tab
            :if={@reassign_tab == :all}
            eligible_members={@eligible_members}
            reassignments={@reassignments}
            sole_owned_projects={@sole_owned_projects}
          />
          <.reassign_per_customer_tab
            :if={@reassign_tab == :per_customer}
            eligible_members={@eligible_members}
            reassignments={@reassignments}
            sole_owned_projects={@sole_owned_projects}
          />
          <.reassign_per_project_tab
            :if={@reassign_tab == :per_project}
            eligible_members={@eligible_members}
            reassignments={@reassignments}
            sole_owned_projects={@sole_owned_projects}
          />
        </div>

        <%!-- Footer --%>
        <div class="flex gap-3 justify-end mt-6 pt-4 border-t border-base-300">
          <button
            phx-click="cancel_remove_member"
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            Cancel
          </button>
          <button
            phx-click="remove_member"
            disabled={!@all_assigned?}
            class={[
              "px-4 py-2 text-sm rounded-lg font-medium transition-colors",
              @all_assigned? && "bg-error text-error-content hover:bg-error/90",
              !@all_assigned? && "bg-base-200 text-base-content/30 cursor-not-allowed"
            ]}
          >
            Remove & Reassign
          </button>
        </div>
      </div>
    </.modal>
    """
  end

  defp reassign_all_tab(assigns) do
    project_ids = Enum.map(assigns.sole_owned_projects, fn {p, _} -> p.id end)
    values = assigns.reassignments |> Map.take(project_ids) |> Map.values() |> Enum.uniq()
    selected = if length(values) == 1, do: hd(values), else: nil
    assigns = assign(assigns, :selected, selected)

    ~H"""
    <div class="space-y-2">
      <label class="block text-xs font-medium text-base-content/60 mb-1">
        New owner for all {@sole_owned_projects |> length()}
        {ngettext("project", "projects", length(@sole_owned_projects))}
      </label>
      <.member_select
        eligible_members={@eligible_members}
        selected={@selected}
        event="reassign_all"
        field="user_id"
      />
    </div>
    """
  end

  defp reassign_per_customer_tab(assigns) do
    groups =
      assigns.sole_owned_projects
      |> Enum.group_by(fn {p, _} -> p.customer end)
      |> Enum.sort_by(fn {c, _} -> c.name end)

    assigns = assign(assigns, :groups, groups)

    ~H"""
    <div class="space-y-4">
      <div :for={{customer, projects} <- @groups} class="space-y-2">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-base-content">{customer.name}</span>
          <span class="text-xs text-base-content/40">
            {length(projects)} {ngettext("project", "projects", length(projects))}
          </span>
        </div>
        <% project_ids = Enum.map(projects, fn {p, _} -> p.id end)
        values = @reassignments |> Map.take(project_ids) |> Map.values() |> Enum.uniq()
        selected = if length(values) == 1, do: hd(values), else: nil %>
        <.member_select
          eligible_members={@eligible_members}
          selected={selected}
          event="reassign_customer"
          field="user_id"
          extra_values={%{"customer_id" => customer.id}}
        />
      </div>
    </div>
    """
  end

  defp reassign_per_project_tab(assigns) do
    ~H"""
    <div class="space-y-3">
      <div :for={{project, est_count} <- @sole_owned_projects} class="space-y-1">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-base-content">{project.name}</span>
          <span class="text-xs text-base-content/40">
            {est_count} {ngettext("estimation", "estimations", est_count)}
          </span>
        </div>
        <.member_select
          eligible_members={@eligible_members}
          selected={Map.get(@reassignments, project.id)}
          event="reassign_project"
          field="user_id"
          extra_values={%{"project_id" => project.id}}
        />
      </div>
    </div>
    """
  end

  defp member_select(assigns) do
    assigns = assign_new(assigns, :extra_values, fn -> %{} end)

    ~H"""
    <select
      phx-change={@event}
      name={@field}
      {@extra_values |> Enum.map(fn {k, v} -> {"phx-value-#{k}", v} end)}
      class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm"
    >
      <option value="">Select member...</option>
      <option
        :for={m <- @eligible_members}
        value={m.user_id}
        selected={@selected == m.user_id}
      >
        {m.user.name || m.user.email}
      </option>
    </select>
    """
  end

  defp confirm_modal(assigns) do
    ~H"""
    <.modal id={@id} show on_cancel={JS.push(@cancel_event)}>
      <div class="text-center">
        <div class="w-12 h-12 rounded-full bg-error/10 flex items-center justify-center mx-auto mb-4">
          <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-error" />
        </div>
        <h3 class="text-lg font-semibold text-base-content mb-2">{@title}</h3>
        <p class="text-sm text-base-content/60 mb-6">{@message}</p>
        <div class="flex gap-3 justify-center">
          <button
            phx-click={@cancel_event}
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            {Map.get(assigns, :cancel_text, "Cancel")}
          </button>
          <button
            phx-click={@confirm_event}
            class="px-4 py-2 bg-error text-error-content text-sm rounded-lg hover:bg-error/90 transition-colors font-medium"
          >
            {@confirm_text}
          </button>
        </div>
      </div>
    </.modal>
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

  def handle_event("switch_reassign_tab", %{"tab" => tab}, socket) when tab in @valid_reassign_tabs do
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

  def handle_event("reassign_customer", %{"customer_id" => customer_id, "user_id" => user_id}, socket) do
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

  def handle_event("reassign_project", %{"project_id" => project_id, "user_id" => user_id}, socket) do
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

          {:error, reason} when reason in [:invalid_project, :invalid_member, :self_reassignment] ->
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

  defp reassignments_complete?(assigns) do
    eligible_ids = MapSet.new(assigns.eligible_members, & &1.user_id)

    Enum.all?(assigns.sole_owned_projects, fn {p, _} ->
      case Map.get(assigns.reassignments, p.id) do
        nil -> false
        "" -> false
        uid -> MapSet.member?(eligible_ids, uid)
      end
    end)
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
