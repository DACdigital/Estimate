defmodule EstimateWeb.SettingsLive.Members do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Page Header --%>
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Members</h1>
        <p class="mt-1 text-gray-500">Manage team members and invitations</p>
      </div>

      <%!-- Invite by Email Card --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden mb-4">
        <div class="p-6">
          <div class="flex items-center justify-between mb-4">
            <p class="text-sm text-gray-600">Invite new members by email address</p>
          </div>

          <.form for={@invite_form} id="invite-form" phx-submit="send_invite" class="flex gap-4">
            <div class="flex-1">
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Email Address</label>
              <input
                type="email"
                name={@invite_form[:email].name}
                value={@invite_form[:email].value}
                placeholder="jane@example.com"
                required
                class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent focus:bg-white text-sm"
              />
            </div>
            <div class="w-48">
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Role</label>
              <select
                name={@invite_form[:role].name}
                class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent focus:bg-white text-sm"
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
                class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
              >
                Invite
              </button>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Generate Invite Code Card --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden mb-8">
        <div class="p-6">
          <div class="flex items-center justify-between mb-4">
            <p class="text-sm text-gray-600">
              Generate a short invite code to share verbally or via text
            </p>
          </div>

          <%= if @generated_code do %>
            <div class="flex items-center gap-4">
              <div class="flex-1 flex items-center justify-center py-3 bg-gray-50 border border-gray-200 rounded-lg">
                <span class="font-mono text-2xl tracking-widest text-gray-900 select-all">
                  {@generated_code}
                </span>
              </div>
              <button
                phx-click="copy_invite_code"
                phx-value-code={@generated_code}
                class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
              >
                Copy
              </button>
              <button
                phx-click="dismiss_generated_code"
                class="px-4 py-2 text-sm text-gray-500 hover:text-gray-900 transition-colors"
              >
                Done
              </button>
            </div>
          <% else %>
            <form phx-submit="generate_invite_code" class="flex gap-4">
              <div class="w-48">
                <label class="block text-xs font-medium text-gray-500 mb-1.5">Role</label>
                <select
                  name="role"
                  class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent focus:bg-white text-sm"
                >
                  <option value="member">Member</option>
                  <option value="admin">Admin</option>
                </select>
              </div>
              <div class="flex items-end">
                <button
                  type="submit"
                  phx-disable-with="Generating..."
                  class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
                >
                  Generate Code
                </button>
              </div>
            </form>
          <% end %>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="border-b border-gray-200 mb-6">
        <div class="flex gap-6">
          <button
            phx-click="switch_tab"
            phx-value-tab="members"
            class={[
              "pb-3 text-sm font-medium border-b-2 transition-colors",
              @current_tab == :members && "border-gray-900 text-gray-900",
              @current_tab != :members && "border-transparent text-gray-500 hover:text-gray-700"
            ]}
          >
            Team Members
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="invites"
            class={[
              "pb-3 text-sm font-medium border-b-2 transition-colors",
              @current_tab == :invites && "border-gray-900 text-gray-900",
              @current_tab != :invites && "border-transparent text-gray-500 hover:text-gray-700"
            ]}
          >
            Pending Invitations
            <%= if length(@invites) > 0 do %>
              <span class="ml-2 px-1.5 py-0.5 text-xs bg-gray-100 text-gray-600 rounded">
                {length(@invites)}
              </span>
            <% end %>
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="requests"
            class={[
              "pb-3 text-sm font-medium border-b-2 transition-colors",
              @current_tab == :requests && "border-gray-900 text-gray-900",
              @current_tab != :requests && "border-transparent text-gray-500 hover:text-gray-700"
            ]}
          >
            Join Requests
            <%= if length(@join_requests) > 0 do %>
              <span class="ml-2 px-1.5 py-0.5 text-xs bg-amber-100 text-amber-700 rounded">
                {length(@join_requests)}
              </span>
            <% end %>
          </button>
        </div>
      </div>

      <%!-- Members List --%>
      <div
        :if={@current_tab == :members}
        class="bg-white border border-gray-200 rounded-xl overflow-hidden"
      >
        <div
          :for={membership <- Enum.sort_by(@members, &(&1.user_id != @current_user.id))}
          class="px-6 py-4 flex items-center justify-between border-b border-gray-100 last:border-b-0"
        >
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-full bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white text-sm font-medium">
              {String.first(membership.user.name || membership.user.email) |> String.upcase()}
            </div>
            <div>
              <div class="flex items-center gap-2">
                <h3 class="text-sm font-medium text-gray-900">{membership.user.name}</h3>
                <span
                  :if={membership.user_id == @current_user.id}
                  class="text-[10px] px-1.5 py-0.5 bg-gray-100 text-gray-500 rounded-full font-medium"
                >
                  You
                </span>
              </div>
              <p class="text-sm text-gray-500">{membership.user.email}</p>
            </div>
          </div>
          <div class="flex items-center gap-4">
            <%= if can_manage?(assigns, membership) && membership.role != "owner" && membership.user_id != @current_user.id do %>
              <form phx-change="change_member_role" phx-value-id={membership.id}>
                <select
                  name="role"
                  class="text-sm px-2 py-1 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
                >
                  <option value="member" selected={membership.role == "member"}>Member</option>
                  <option value="admin" selected={membership.role == "admin"}>Admin</option>
                </select>
              </form>
              <button
                phx-click="confirm_remove_member"
                phx-value-id={membership.id}
                class="text-gray-400 hover:text-red-600 transition-colors"
              >
                <.icon name="hero-x-mark" class="w-5 h-5" />
              </button>
            <% else %>
              <span class="text-sm text-gray-500 capitalize">{membership.role}</span>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Invitations List --%>
      <div
        :if={@current_tab == :invites}
        class="bg-white border border-gray-200 rounded-xl overflow-hidden"
      >
        <%= if @invites == [] do %>
          <div class="px-6 py-12 text-center">
            <p class="text-sm text-gray-500">No pending invitations</p>
          </div>
        <% else %>
          <div
            :for={invite <- @invites}
            class="px-6 py-4 flex items-center justify-between border-b border-gray-100 last:border-b-0"
          >
            <div class="flex items-center gap-3">
              <%= if invite.code && !invite.email do %>
                <div class="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center text-gray-400">
                  <.icon name="hero-key" class="w-5 h-5" />
                </div>
                <div>
                  <div class="flex items-center gap-2">
                    <span class="font-mono text-sm font-medium text-gray-900 tracking-wider">
                      {invite.code}
                    </span>
                    <span class="px-1.5 py-0.5 text-xs bg-gray-100 text-gray-500 rounded">
                      code
                    </span>
                  </div>
                  <p class="text-sm text-gray-500">
                    Expires {Calendar.strftime(invite.expires_at, "%b %d, %Y")}
                  </p>
                </div>
              <% else %>
                <div class="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center text-gray-400">
                  <.icon name="hero-envelope" class="w-5 h-5" />
                </div>
                <div>
                  <h3 class="text-sm font-medium text-gray-900">{invite.email}</h3>
                  <p class="text-sm text-gray-500">
                    Expires {Calendar.strftime(invite.expires_at, "%b %d, %Y")}
                  </p>
                </div>
              <% end %>
            </div>
            <div class="flex items-center gap-4">
              <span class="text-sm text-gray-500 capitalize">{invite.role}</span>
              <div class="flex items-center gap-2">
                <%= if invite.code && !invite.email do %>
                  <button
                    phx-click="copy_invite_code"
                    phx-value-code={invite.code}
                    class="text-sm text-gray-500 hover:text-gray-900 transition-colors"
                  >
                    Copy Code
                  </button>
                <% else %>
                  <button
                    phx-click="copy_invite_link"
                    phx-value-token={invite.token}
                    class="text-sm text-gray-500 hover:text-gray-900 transition-colors"
                  >
                    Copy Link
                  </button>
                <% end %>
                <button
                  :if={@is_admin}
                  phx-click="confirm_cancel_invite"
                  phx-value-id={invite.id}
                  class="text-sm text-gray-500 hover:text-red-600 transition-colors"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Join Requests List --%>
      <div
        :if={@current_tab == :requests}
        class="bg-white border border-gray-200 rounded-xl overflow-hidden"
      >
        <%= if @join_requests == [] do %>
          <div class="px-6 py-12 text-center">
            <p class="text-sm text-gray-500">No pending join requests</p>
          </div>
        <% else %>
          <div
            :for={request <- @join_requests}
            class="px-6 py-4 flex items-center justify-between border-b border-gray-100 last:border-b-0"
          >
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-full bg-amber-100 flex items-center justify-center text-amber-600 text-sm font-medium">
                {String.first(request.user.name || request.user.email) |> String.upcase()}
              </div>
              <div>
                <h3 class="text-sm font-medium text-gray-900">{request.user.name}</h3>
                <p class="text-sm text-gray-500">{request.user.email}</p>
                <p class="text-xs text-gray-400">
                  Requested {Calendar.strftime(request.inserted_at, "%b %d, %Y")}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <button
                phx-click="approve_request"
                phx-value-id={request.id}
                class="px-3 py-1.5 text-sm font-medium text-green-700 bg-green-50 rounded-lg hover:bg-green-100 transition-colors"
              >
                Approve
              </button>
              <button
                phx-click="reject_request"
                phx-value-id={request.id}
                class="px-3 py-1.5 text-sm font-medium text-red-700 bg-red-50 rounded-lg hover:bg-red-100 transition-colors"
              >
                Reject
              </button>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Remove Member Modal --%>
      <.modal
        :if={@removing_member}
        id="remove-member-modal"
        show
        on_cancel={JS.push("cancel_remove_member")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Remove Member</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to remove <span class="font-medium text-gray-900"><%= @removing_member.user.name || @removing_member.user.email %></span>?
            They will lose access to this organization.
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_remove_member"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="remove_member"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Remove
            </button>
          </div>
        </div>
      </.modal>

      <%!-- Cancel Invite Modal --%>
      <.modal
        :if={@canceling_invite}
        id="cancel-invite-modal"
        show
        on_cancel={JS.push("dismiss_cancel_invite")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Cancel Invitation</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to cancel the invitation to <span class="font-medium text-gray-900"><%= @canceling_invite.email %></span>?
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="dismiss_cancel_invite"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Keep Invitation
            </button>
            <button
              phx-click="cancel_invite"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Cancel Invitation
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org_id = socket.assigns.org_id
    members = Accounts.list_organization_members(org_id)
    invites = Accounts.list_organization_invites(org_id)
    join_requests = Accounts.list_pending_join_requests(org_id)

    {:ok,
     socket
     |> assign(:page_title, "Members")
     |> assign(:active_tab, :settings)
     |> assign(:settings_page, :members)
     |> assign(:current_tab, :members)
     |> assign(:members, members)
     |> assign(:invites, invites)
     |> assign(:join_requests, join_requests)
     |> assign(:removing_member, nil)
     |> assign(:canceling_invite, nil)
     |> assign(:is_admin, socket.assigns.current_membership.role in ["owner", "admin"])
     |> assign(:generated_code, nil)
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: "invite"))}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :current_tab, String.to_existing_atom(tab))}
  end

  def handle_event("send_invite", %{"invite" => params}, socket) do
    unless can_manage?(socket.assigns, nil) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      user = socket.assigns.current_user
      org_id = socket.assigns.org_id

      case Accounts.create_invite(org_id, atomize_keys(params), user.id) do
        {:ok, _invite} ->
          invites = Accounts.list_organization_invites(org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Invitation sent!")
           |> assign(:invites, invites)
           |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: "invite"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not send invitation")}
      end
    end
  end

  def handle_event("change_member_role", %{"id" => id, "role" => role}, socket) do
    membership = Enum.find(socket.assigns.members, &(&1.id == id))

    if membership && can_manage?(socket.assigns, membership) &&
         membership.role != "owner" && membership.user_id != socket.assigns.current_user.id do
      case Accounts.update_membership_role(membership, role) do
        {:ok, _} ->
          members = Accounts.list_organization_members(socket.assigns.org_id)
          {:noreply, socket |> put_flash(:info, "Role updated") |> assign(:members, members)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update role")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized")}
    end
  end

  def handle_event("confirm_remove_member", %{"id" => id}, socket) do
    membership = Enum.find(socket.assigns.members, &(&1.id == id))
    {:noreply, assign(socket, :removing_member, membership)}
  end

  def handle_event("cancel_remove_member", _params, socket) do
    {:noreply, assign(socket, :removing_member, nil)}
  end

  def handle_event("remove_member", _params, socket) do
    membership = socket.assigns.removing_member

    if membership && can_manage?(socket.assigns, membership) && membership.role != "owner" do
      Accounts.delete_membership(membership)
      members = Accounts.list_organization_members(socket.assigns.org_id)

      {:noreply,
       socket
       |> put_flash(:info, "Member removed")
       |> assign(:members, members)
       |> assign(:removing_member, nil)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Cannot remove this member")
       |> assign(:removing_member, nil)}
    end
  end

  def handle_event("confirm_cancel_invite", %{"id" => id}, socket) do
    invite = Enum.find(socket.assigns.invites, &(&1.id == id))
    {:noreply, assign(socket, :canceling_invite, invite)}
  end

  def handle_event("dismiss_cancel_invite", _params, socket) do
    {:noreply, assign(socket, :canceling_invite, nil)}
  end

  def handle_event("cancel_invite", _params, socket) do
    unless can_manage?(socket.assigns, nil) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      invite = socket.assigns.canceling_invite

      if invite do
        Accounts.delete_invite(invite)
        invites = Accounts.list_organization_invites(socket.assigns.org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Invitation cancelled")
         |> assign(:invites, invites)
         |> assign(:canceling_invite, nil)}
      else
        {:noreply, assign(socket, :canceling_invite, nil)}
      end
    end
  end

  def handle_event("generate_invite_code", %{"role" => role}, socket) do
    unless can_manage?(socket.assigns, nil) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      user = socket.assigns.current_user
      org_id = socket.assigns.org_id

      case Accounts.create_invite_code(org_id, role, user.id) do
        {:ok, invite} ->
          invites = Accounts.list_organization_invites(org_id)

          {:noreply,
           socket
           |> assign(:generated_code, invite.code)
           |> assign(:invites, invites)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not generate invite code")}
      end
    end
  end

  def handle_event("copy_invite_code", %{"code" => code}, socket) do
    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: code})
     |> put_flash(:info, "Code copied to clipboard!")}
  end

  def handle_event("dismiss_generated_code", _params, socket) do
    {:noreply, assign(socket, :generated_code, nil)}
  end

  def handle_event("copy_invite_link", %{"token" => token}, socket) do
    url = url(~p"/invites/#{token}")

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: url})
     |> put_flash(:info, "Link copied to clipboard!")}
  end

  def handle_event("approve_request", %{"id" => id}, socket) do
    unless can_manage?(socket.assigns, nil) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      request = Accounts.get_join_request!(id)
      user = socket.assigns.current_user

      case Accounts.approve_join_request(request, user.id) do
        {:ok, _} ->
          org_id = socket.assigns.org_id
          members = Accounts.list_organization_members(org_id)
          join_requests = Accounts.list_pending_join_requests(org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Request approved!")
           |> assign(:members, members)
           |> assign(:join_requests, join_requests)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not approve request")}
      end
    end
  end

  def handle_event("reject_request", %{"id" => id}, socket) do
    unless can_manage?(socket.assigns, nil) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      request = Accounts.get_join_request!(id)
      user = socket.assigns.current_user

      case Accounts.reject_join_request(request, user.id) do
        {:ok, _} ->
          join_requests = Accounts.list_pending_join_requests(socket.assigns.org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Request rejected")
           |> assign(:join_requests, join_requests)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not reject request")}
      end
    end
  end

  defp can_manage?(assigns, _membership) do
    assigns.current_membership.role in ["owner", "admin"]
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
