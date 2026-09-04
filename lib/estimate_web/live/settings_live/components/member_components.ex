defmodule EstimateWeb.SettingsLive.Components.MemberComponents do
  use EstimateWeb, :html

  alias EstimateWeb.Format

  attr :invite_form, :map, required: true

  def invite_by_email_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
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

  attr :generated_code, :string, default: nil

  def invite_code_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
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

  attr :join_url, :string, required: true

  def join_link_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
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

  attr :members, :list, required: true
  attr :current_user, :map, required: true
  attr :current_membership, :map, required: true

  def members_tab(assigns) do
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
              <.badge :if={membership.user_id == @current_user.id} variant={:neutral}>You</.badge>
              <%= if Estimate.Accounts.User.totp_enabled?(membership.user) do %>
                <.badge variant={:success}>2FA</.badge>
              <% else %>
                <.badge variant={:muted}>No 2FA</.badge>
              <% end %>
            </div>
            <p class="text-sm text-base-content/60">{membership.user.email}</p>
            <p class="text-xs text-base-content/40">
              Active {time_ago(membership.user.last_active_at)}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
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
              :if={Estimate.Accounts.User.totp_enabled?(membership.user)}
              phx-click="confirm_disable_2fa"
              phx-value-id={membership.user.id}
              title="Disable 2FA"
              class="text-base-content/40 hover:text-warning transition-colors"
            >
              <.icon name="hero-shield-exclamation" class="w-5 h-5" />
            </button>
            <button
              :if={@current_membership.role == "owner"}
              phx-click="confirm_transfer_ownership"
              phx-value-id={membership.id}
              title="Make owner"
              aria-label="Make owner"
              class="text-base-content/40 hover:text-base-content/70 transition-colors"
            >
              <.icon name="hero-key" class="w-4 h-4" />
            </button>
            <button
              phx-click="confirm_remove_member"
              phx-value-id={membership.id}
              class="flex items-center text-base-content/40 hover:text-error transition-colors"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          <% else %>
            <span class="text-sm text-base-content/60 capitalize">{membership.role}</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :invites, :list, required: true
  attr :is_admin, :boolean, required: true

  def invitations_tab(assigns) do
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
                  Expires {Format.date(invite.expires_at)}
                </p>
              </div>
            <% else %>
              <div class="w-10 h-10 rounded-full bg-base-200 flex items-center justify-center text-base-content/40">
                <.icon name="hero-envelope" class="w-5 h-5" />
              </div>
              <div>
                <h3 class="text-sm font-medium text-base-content">{invite.email}</h3>
                <p class="text-sm text-base-content/60">
                  Expires {Format.date(invite.expires_at)}
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

  attr :join_requests, :list, required: true
  attr :is_admin, :boolean, required: true

  def join_requests_tab(assigns) do
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
            <.avatar
              name={request.user.name || request.user.email}
              seed={request.user.id}
              type={:pending}
            />
            <div>
              <h3 class="text-sm font-medium text-base-content">{request.user.name}</h3>
              <p class="text-sm text-base-content/60">{request.user.email}</p>
              <p class="text-xs text-base-content/40">
                Requested {Format.date(request.inserted_at)}
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
end
