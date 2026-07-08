defmodule EstimateWeb.SettingsLive.Trash do
  use EstimateWeb, :live_view

  alias Estimate.EstimationEngine

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Deleted Estimations</h1>
        <p class="mt-1 text-base-content/60">
          Manage soft-deleted estimations across your organization
        </p>
      </div>

      <%= if @deleted_estimations == [] do %>
        <div class="bg-base-100 border border-base-300 rounded-xl p-12 text-center">
          <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-success/10 flex items-center justify-center">
            <.icon name="hero-check-circle" class="w-6 h-6 text-success" />
          </div>
          <p class="text-sm font-medium text-base-content">No deleted estimations</p>
          <p class="text-sm text-base-content/60 mt-1">Trash is empty</p>
        </div>
      <% else %>
        <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
          <%= for estimation <- @deleted_estimations do %>
            <%= if @permanently_deleting == estimation.id do %>
              <div class="flex items-center justify-between px-6 py-4 bg-error/5 border-b border-base-content/10 last:border-b-0">
                <span class="text-sm text-error font-medium">
                  Permanently delete "{estimation.name}"?
                </span>
                <div class="flex items-center gap-2">
                  <button
                    phx-click="cancel_permanent_delete"
                    class="text-xs text-base-content/60 hover:text-base-content px-2 py-1"
                  >
                    Cancel
                  </button>
                  <button
                    phx-click="permanent_delete_estimation"
                    phx-value-id={estimation.id}
                    class="text-xs text-error font-medium px-2 py-1"
                  >
                    Delete Forever
                  </button>
                </div>
              </div>
            <% else %>
              <div class="flex items-center border-b border-base-content/10 last:border-b-0">
                <div class="flex-1 px-6 py-4">
                  <h3 class="text-sm font-medium text-base-content/50">{estimation.name}</h3>
                  <p class="text-xs text-base-content/40 mt-0.5">
                    {if(estimation.project.customer, do: estimation.project.customer.name <> " › ", else: "")}{estimation.project.name}
                    · Deleted {Calendar.strftime(estimation.deleted_at, "%b %d, %Y")}
                  </p>
                </div>
                <div class="flex items-center gap-2 px-4 pr-6 shrink-0">
                  <button
                    phx-click="restore_estimation"
                    phx-value-id={estimation.id}
                    class="text-base-content/40 hover:text-info transition-colors"
                    title="Restore estimation"
                  >
                    <.icon name="hero-arrow-uturn-left" class="w-4 h-4" />
                  </button>
                  <button
                    phx-click="confirm_permanent_delete"
                    phx-value-id={estimation.id}
                    class="text-base-content/40 hover:text-error transition-colors"
                    title="Delete forever"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    unless admin?(socket.assigns.current_membership) do
      {:ok,
       socket
       |> put_flash(:error, "Not authorized")
       |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}")}
    else
      org_id = socket.assigns.org_id
      deleted = EstimationEngine.list_deleted_estimations_for_org(org_id, 50)

      {:ok,
       socket
       |> assign(:page_title, "Deleted Estimations")
       |> assign(:active_tab, :settings)
       |> assign(:deleted_estimations, deleted)
       |> assign(:permanently_deleting, nil)}
    end
  end

  @impl true
  def handle_event("restore_estimation", %{"id" => id}, socket) do
    require_admin(socket, fn ->
      estimation = Enum.find(socket.assigns.deleted_estimations, &(&1.id == id))

      if estimation do
        case EstimationEngine.restore_estimation(estimation) do
          {:ok, _} ->
            deleted = EstimationEngine.list_deleted_estimations_for_org(socket.assigns.org_id, 50)

            {:noreply,
             socket
             |> assign(:deleted_estimations, deleted)
             |> put_flash(:info, "Estimation restored")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not restore estimation")}
        end
      else
        {:noreply, put_flash(socket, :error, "Estimation not found")}
      end
    end)
  end

  def handle_event("confirm_permanent_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :permanently_deleting, id)}
  end

  def handle_event("cancel_permanent_delete", _params, socket) do
    {:noreply, assign(socket, :permanently_deleting, nil)}
  end

  def handle_event("permanent_delete_estimation", %{"id" => id}, socket) do
    require_admin(socket, fn ->
      estimation = Enum.find(socket.assigns.deleted_estimations, &(&1.id == id))

      if estimation do
        case EstimationEngine.hard_delete_estimation(estimation) do
          {:ok, _} ->
            deleted = EstimationEngine.list_deleted_estimations_for_org(socket.assigns.org_id, 50)

            {:noreply,
             socket
             |> assign(:deleted_estimations, deleted)
             |> assign(:permanently_deleting, nil)
             |> put_flash(:info, "Estimation permanently deleted")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not delete estimation")
             |> assign(:permanently_deleting, nil)}
        end
      else
        {:noreply,
         socket
         |> put_flash(:error, "Estimation not found")
         |> assign(:permanently_deleting, nil)}
      end
    end)
  end
end
