defmodule EstimateWeb.Components.SearchComponent do
  use EstimateWeb, :live_component

  alias Estimate.Search

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       query: "",
       results: [],
       show_results: false,
       selected_index: 0
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative" id={@id} phx-hook="SearchFocus" phx-target={@myself}>
      <div class="relative">
        <.icon
          name="hero-magnifying-glass"
          class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400"
        />
        <input
          type="text"
          id={"#{@id}-input"}
          value={@query}
          placeholder="Search..."
          phx-keyup="search"
          phx-debounce="150"
          phx-target={@myself}
          phx-focus="show_results"
          autocomplete="off"
          class="w-full pl-9 pr-16 py-1.5 text-sm bg-gray-50 border border-gray-200 rounded-lg text-gray-900 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
        />
        <div class="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1">
          <button
            :if={@query != ""}
            type="button"
            phx-click="clear"
            phx-target={@myself}
            class="text-gray-400 hover:text-gray-600"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
          <kbd
            :if={@query == ""}
            class="hidden sm:inline-flex items-center px-1.5 py-0.5 text-xs text-gray-400 bg-gray-100 rounded"
          >
            /
          </kbd>
        </div>
      </div>

      <div
        :if={@show_results && (@results != [] || String.length(@query) >= 2)}
        id={"#{@id}-dropdown"}
        class="absolute top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-lg shadow-lg overflow-hidden z-50"
        phx-click-away="hide_results"
        phx-target={@myself}
      >
        <div
          :if={@results == [] && String.length(@query) >= 2}
          class="px-4 py-3 text-sm text-gray-500"
        >
          No results for "{@query}"
        </div>

        <div :if={@results != []} class="max-h-80 overflow-y-auto">
          <%= for {result, idx} <- Enum.with_index(@results) do %>
            <.link
              navigate={result_path(result, @org_id)}
              class={[
                "flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 transition-colors",
                idx == @selected_index && "bg-gray-50"
              ]}
              phx-click="hide_results"
              phx-target={@myself}
            >
              <span class={["text-xs font-medium px-2 py-0.5 rounded", type_badge_class(result.type)]}>
                {type_label(result.type)}
              </span>
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-gray-900 truncate">{result.title}</p>
                <p :if={result.subtitle} class="text-xs text-gray-500 truncate">
                  {result.subtitle}
                </p>
              </div>
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Search.search(socket.assigns.org_id, query)
      else
        []
      end

    {:noreply,
     assign(socket,
       query: query,
       results: results,
       show_results: true,
       selected_index: 0
     )}
  end

  def handle_event("clear", _, socket) do
    {:noreply,
     assign(socket,
       query: "",
       results: [],
       show_results: false,
       selected_index: 0
     )}
  end

  def handle_event("show_results", _, socket) do
    {:noreply, assign(socket, show_results: socket.assigns.query != "")}
  end

  def handle_event("hide_results", _, socket) do
    {:noreply, assign(socket, show_results: false)}
  end

  def handle_event("navigate_results", %{"key" => "ArrowDown"}, socket) do
    max_idx = length(socket.assigns.results) - 1
    new_idx = min(socket.assigns.selected_index + 1, max_idx)
    {:noreply, assign(socket, selected_index: new_idx)}
  end

  def handle_event("navigate_results", %{"key" => "ArrowUp"}, socket) do
    new_idx = max(socket.assigns.selected_index - 1, 0)
    {:noreply, assign(socket, selected_index: new_idx)}
  end

  def handle_event("navigate_results", %{"key" => "Enter"}, socket) do
    case Enum.at(socket.assigns.results, socket.assigns.selected_index) do
      nil ->
        {:noreply, socket}

      result ->
        path = result_path(result, socket.assigns.org_id)
        {:noreply, push_navigate(socket, to: path)}
    end
  end

  def handle_event("navigate_results", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, show_results: false)}
  end

  def handle_event("navigate_results", _, socket) do
    {:noreply, socket}
  end

  defp result_path(%{type: "customer", path_ids: %{"customer_id" => customer_id}}, org_id) do
    ~p"/org/#{org_id}/customers/#{customer_id}"
  end

  defp result_path(%{type: "project", path_ids: %{"project_id" => project_id}}, org_id) do
    ~p"/org/#{org_id}/projects/#{project_id}"
  end

  defp result_path(
         %{
           type: "estimation",
           path_ids: %{"project_id" => project_id, "estimation_id" => est_id}
         },
         org_id
       ) do
    ~p"/org/#{org_id}/projects/#{project_id}/estimations/#{est_id}/estimator"
  end

  defp type_label("customer"), do: "Customer"
  defp type_label("project"), do: "Project"
  defp type_label("estimation"), do: "Estimation"

  defp type_badge_class("customer"), do: "bg-blue-100 text-blue-700"
  defp type_badge_class("project"), do: "bg-green-100 text-green-700"
  defp type_badge_class("estimation"), do: "bg-purple-100 text-purple-700"
end
