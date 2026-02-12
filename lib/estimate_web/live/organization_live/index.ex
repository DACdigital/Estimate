defmodule EstimateWeb.OrganizationLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full max-w-2xl mx-auto">
      <h1 class="text-3xl font-bold text-center text-gray-900 mb-2">
        Select an Organization
      </h1>
      <p class="text-center text-gray-500 mb-8">
        Choose an organization to continue
      </p>

      <div class="space-y-3">
        <.link
          :for={{org, role} <- @organizations}
          navigate={~p"/org/#{org.id}"}
          class="flex items-center gap-4 p-4 bg-white border border-gray-200 rounded-xl hover:border-gray-300 hover:shadow-sm transition-all group"
        >
          <div class="w-12 h-12 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-semibold text-lg shrink-0">
            {String.first(org.name)}
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="font-semibold text-gray-900 truncate">{org.name}</h3>
            <span class="text-sm text-gray-500 capitalize">{role}</span>
          </div>
          <div class="text-gray-400 group-hover:text-gray-600 transition-colors">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
            </svg>
          </div>
        </.link>

        <div :if={@organizations == []} class="text-center py-12 text-gray-500">
          You're not a member of any organization yet.
        </div>
      </div>

      <%!-- Join with Code --%>
      <div class="mt-6 p-4 bg-white border border-gray-200 rounded-xl">
        <form phx-submit="join_with_code" class="flex gap-3 items-end">
          <div class="flex-1">
            <label class="block text-xs font-medium text-gray-500 mb-1.5">Have an invite code?</label>
            <input
              type="text"
              name="code"
              value={@invite_code}
              placeholder="e.g. XK7F2MPA"
              maxlength="8"
              class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent focus:bg-white text-sm font-mono tracking-wider uppercase"
            />
          </div>
          <button
            type="submit"
            phx-disable-with="Joining..."
            class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
          >
            Join
          </button>
        </form>
      </div>

      <div class="relative my-8">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-gray-200"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="px-4 bg-gray-50 text-gray-500">or</span>
        </div>
      </div>

      <.link
        patch={~p"/organizations/new"}
        class="flex items-center justify-center gap-2 w-full py-3 px-4 border-2 border-dashed border-gray-300 rounded-xl text-gray-600 hover:border-gray-400 hover:text-gray-900 transition-colors"
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
        Create New Organization
      </.link>

      <.modal
        :if={@live_action == :new}
        id="new-org-modal"
        show
        on_cancel={JS.patch(~p"/organizations")}
      >
        <div class="text-center mb-6">
          <h2 class="text-2xl font-bold text-gray-900">Create Organization</h2>
          <p class="text-gray-500 mt-1">Start collaborating with your team</p>
        </div>

        <form id="org-form" phx-submit="save" phx-change="validate" class="space-y-4">
          <div>
            <input
              type="text"
              name="organization[name]"
              value={@form && @form[:name].value}
              placeholder="Organization Name"
              required
              class="w-full px-4 py-3 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
            />
            <p
              :for={error <- @form[:name].errors}
              :if={@form && @form[:name].errors != []}
              class="mt-1 text-sm text-red-600"
            >
              {translate_error(error)}
            </p>
          </div>

          <button
            type="submit"
            phx-disable-with="Creating..."
            class="w-full py-3 px-4 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors"
          >
            Create Organization
          </button>
        </form>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    organizations = Accounts.list_user_organizations(socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign(:organizations, organizations)
     |> assign(:invite_code, "")
     |> assign(:form, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    changeset = Accounts.change_organization(%Accounts.Organization{})

    socket
    |> assign(:page_title, "New Organization")
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Organizations")
    |> assign(:form, nil)
  end

  @impl true
  def handle_event("validate", %{"organization" => org_params}, socket) do
    changeset =
      %Accounts.Organization{}
      |> Accounts.change_organization(org_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("join_with_code", %{"code" => code}, socket) do
    user = socket.assigns.current_user

    case Accounts.get_valid_invite_by_code(code) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid or expired invite code")
         |> assign(:invite_code, code)}

      invite ->
        case Accounts.accept_invite(invite, user.id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Joined #{invite.organization.name}!")
             |> push_navigate(to: ~p"/org/#{invite.organization_id}")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not join — you may already be a member")
             |> assign(:invite_code, code)}
        end
    end
  end

  def handle_event("save", %{"organization" => org_params}, socket) do
    user = socket.assigns.current_user

    case Accounts.create_organization_with_owner(org_params, user.id) do
      {:ok, org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization created successfully")
         |> push_navigate(to: ~p"/org/#{org.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
