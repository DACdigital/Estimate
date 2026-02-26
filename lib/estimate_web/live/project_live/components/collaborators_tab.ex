defmodule EstimateWeb.ProjectLive.Components.CollaboratorsTab do
  use EstimateWeb, :html

  attr :collaborators, :list, required: true
  attr :available_members, :list, required: true
  attr :current_user, :map, required: true
  attr :current_collaborator, :map, default: nil
  attr :can_manage_collaborators, :boolean, required: true
  attr :member_search, :string, required: true
  attr :show_member_dropdown, :boolean, required: true
  attr :selected_member, :map, default: nil
  attr :selected_role, :string, required: true
  attr :filtered_members, :list, required: true

  def tab_collaborators(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Add Collaborator --%>
      <div
        :if={@can_manage_collaborators}
        class="bg-base-100 border border-base-300 rounded-xl"
      >
        <form phx-change="collaborator_form_change" phx-submit="add_collaborator" class="p-6">
          <h2 class="text-lg font-semibold text-base-content mb-4">Add Collaborator</h2>
          <div class="flex gap-4">
            <div class="flex-1 relative">
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Member</label>
              <%= if @selected_member do %>
                <div class="flex items-center gap-2 px-3 py-2 bg-base-200 border border-base-300 rounded-lg">
                  <.avatar
                    name={@selected_member.name || @selected_member.email}
                    seed={@selected_member.id}
                    size={:xs}
                  />
                  <span class="text-sm text-base-content">
                    {@selected_member.name || @selected_member.email}
                  </span>
                  <button
                    type="button"
                    phx-click="clear_selected_member"
                    class="ml-auto text-base-content/40 hover:text-base-content/70"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </div>
              <% else %>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <.icon name="hero-magnifying-glass" class="w-4 h-4 text-base-content/40" />
                  </div>
                  <input
                    type="text"
                    name="member_search"
                    value={@member_search}
                    placeholder="Search members..."
                    phx-focus="open_member_dropdown"
                    phx-click-away="close_member_dropdown"
                    phx-debounce="100"
                    autocomplete="off"
                    class="w-full pl-9 pr-3 py-2 bg-base-200 border border-base-300 rounded-lg text-sm"
                  />
                </div>
                <div
                  :if={@show_member_dropdown && @filtered_members != []}
                  class="absolute z-10 mt-1 w-full bg-base-100 border border-base-300 rounded-lg shadow-lg max-h-48 overflow-y-auto"
                >
                  <button
                    :for={membership <- @filtered_members}
                    type="button"
                    phx-click="select_member"
                    phx-value-user-id={membership.user.id}
                    class="w-full px-3 py-2 flex items-center gap-3 hover:bg-base-200 text-left"
                  >
                    <.avatar
                      name={membership.user.name || membership.user.email}
                      seed={membership.user.id}
                      size={:sm}
                    />
                    <div class="min-w-0">
                      <p class="text-sm font-medium text-base-content truncate">
                        {membership.user.name || membership.user.email}
                      </p>
                      <p class="text-xs text-base-content/60 truncate">{membership.user.email}</p>
                    </div>
                    <span class="ml-auto text-xs text-base-content/40 capitalize flex-shrink-0">
                      {membership.role}
                    </span>
                  </button>
                </div>
              <% end %>
            </div>
            <div class="w-36">
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Role</label>
              <select
                name="collaborator_role"
                class="w-full px-3 py-2 bg-base-200 border border-base-300 rounded-lg text-sm"
              >
                <option value="viewer" selected={@selected_role == "viewer"}>Viewer</option>
                <option value="editor" selected={@selected_role == "editor"}>Editor</option>
                <option value="owner" selected={@selected_role == "owner"}>Owner</option>
              </select>
            </div>
            <div class="flex items-end">
              <button
                type="submit"
                disabled={is_nil(@selected_member)}
                class={"px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg font-medium transition-colors #{if is_nil(@selected_member), do: "opacity-50 cursor-not-allowed", else: "hover:bg-neutral/90"}"}
              >
                Add
              </button>
            </div>
          </div>
        </form>
      </div>

      <%!-- Collaborators List --%>
      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <div class="px-6 py-4 border-b border-base-content/10">
          <h2 class="text-lg font-semibold text-base-content">Collaborators</h2>
        </div>
        <%= if @collaborators == [] do %>
          <div class="px-6 py-12 text-center">
            <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-base-200 flex items-center justify-center">
              <.icon name="hero-users" class="w-6 h-6 text-base-content/40" />
            </div>
            <p class="text-sm font-medium text-base-content">No collaborators</p>
            <p class="text-sm text-base-content/60 mt-1">Add team members to this project.</p>
          </div>
        <% else %>
          <div
            :for={collab <- Enum.sort_by(@collaborators, &(&1.user_id != @current_user.id))}
            class="px-6 py-4 flex items-center justify-between border-b border-base-content/10 last:border-b-0"
          >
            <div class="flex items-center gap-3">
              <.avatar name={collab.user.name || collab.user.email} seed={collab.user.id} />
              <div>
                <div class="flex items-center gap-2">
                  <h3 class="text-sm font-medium text-base-content">{collab.user.name}</h3>
                  <span
                    :if={collab.user_id == @current_user.id}
                    class="text-[10px] px-1.5 py-0.5 bg-base-200 text-base-content/60 rounded-full font-medium"
                  >
                    You
                  </span>
                </div>
                <p class="text-sm text-base-content/60">{collab.user.email}</p>
              </div>
            </div>
            <div class="flex items-center gap-4">
              <%= if can_change_role?(@can_manage_collaborators, @current_user, collab) do %>
                <form phx-change="change_collaborator_role" phx-value-id={collab.id}>
                  <select
                    name="role"
                    class="text-sm px-2 py-1 border border-base-300 rounded-lg"
                  >
                    <option value="viewer" selected={collab.role == "viewer"}>Viewer</option>
                    <option value="editor" selected={collab.role == "editor"}>Editor</option>
                    <option value="owner" selected={collab.role == "owner"}>Owner</option>
                  </select>
                </form>
              <% else %>
                <span class="text-sm text-base-content/60 capitalize">{collab.role}</span>
              <% end %>
              <%= if can_remove_collaborator?(@can_manage_collaborators, @current_user, @current_collaborator, collab) do %>
                <button
                  phx-click="confirm_remove_collaborator"
                  phx-value-id={collab.id}
                  class="text-base-content/40 hover:text-error transition-colors"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def can_change_role?(can_manage, current_user, collab) do
    can_manage && collab.user_id != current_user.id
  end

  def can_remove_collaborator?(can_manage, current_user, current_collaborator, collab) do
    cond do
      collab.user_id == current_user.id ->
        false

      collab.role == "owner" ->
        current_collaborator && current_collaborator.role == "owner"

      true ->
        can_manage
    end
  end
end
