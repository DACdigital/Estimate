defmodule EstimateWeb.SettingsLive.Ai do
  use EstimateWeb, :live_view

  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">AI Integration</h1>
        <p class="mt-1 text-gray-500">Connect to OpenRouter to enhance descriptions with AI</p>
      </div>

      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <.form for={@ai_form} id="ai-settings-form" phx-submit="save_ai_settings">
          <div class="p-6">
            <div class="space-y-4 max-w-md">
              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1.5">
                  API Key
                  <span
                    :if={@ai_configured}
                    class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-green-50 text-green-700 rounded-full"
                  >
                    <svg class="w-2.5 h-2.5" fill="currentColor" viewBox="0 0 8 8"><circle cx="4" cy="4" r="4" /></svg>
                    Connected · {@ai_key_masked}
                  </span>
                </label>
                <input
                  type="password"
                  name="ai[openrouter_api_key]"
                  placeholder={if @ai_configured, do: "Paste new key to replace", else: "sk-or-..."}
                  autocomplete="off"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                />
              </div>
              <div class="relative" phx-click-away="close_model_dropdown">
                <label class="block text-xs font-medium text-gray-500 mb-1.5">Model</label>
                <input
                  type="text"
                  name="ai[openrouter_model]"
                  value={@model_query}
                  phx-keyup="search_models"
                  phx-debounce="300"
                  phx-focus="open_model_dropdown"
                  placeholder="Search models..."
                  autocomplete="off"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                />
                <div
                  :if={@model_dropdown_open && @model_results != []}
                  class="absolute z-10 mt-1 w-full bg-white border border-gray-200 rounded-lg shadow-lg max-h-60 overflow-y-auto"
                >
                  <button
                    :for={model <- @model_results}
                    type="button"
                    phx-click="select_model"
                    phx-value-id={model.id}
                    class="w-full text-left px-3 py-2 hover:bg-gray-50 border-b border-gray-100 last:border-0"
                  >
                    <div class="text-sm font-medium text-gray-900">{model.name || model.id}</div>
                    <div class="text-xs text-gray-500">{model.id} · {format_context(model.context_length)}</div>
                  </button>
                </div>
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1.5">
                  System Prompt <span class="text-gray-400">(optional)</span>
                </label>
                <textarea
                  name="ai[openrouter_system_prompt]"
                  rows="3"
                  placeholder="Default: enhance description for estimation..."
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm resize-none"
                ><%= @ai_form[:openrouter_system_prompt].value %></textarea>
              </div>
            </div>
          </div>
          <div class="px-6 py-3 bg-gray-50 border-t border-gray-200 flex items-center justify-between">
            <p class="text-sm text-gray-500">API key is encrypted at rest.</p>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-1.5 bg-gray-900 text-white text-sm rounded-md hover:bg-gray-800 transition-colors font-medium"
            >
              Save
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_organization

    unless admin?(socket.assigns.current_membership) do
      {:ok,
       socket
       |> put_flash(:error, "Not authorized")
       |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/settings")}
    else
      ai_changeset = Estimate.Accounts.Organization.ai_settings_changeset(org, %{})

      {:ok,
       socket
       |> assign(:page_title, "AI Integration")
       |> assign(:active_tab, :settings)
       |> assign(:settings_page, :ai)
       |> assign(:ai_form, to_form(ai_changeset, as: :ai))
       |> assign(:ai_configured, org.encrypted_openrouter_api_key != nil)
       |> assign(:ai_key_masked, Organizations.mask_api_key(org))
       |> assign(:model_query, org.openrouter_model || "")
       |> assign(:model_results, [])
       |> assign(:model_dropdown_open, false)}
    end
  end

  @impl true
  def handle_event("search_models", %{"value" => query}, socket) do
    case Estimate.AI.OpenRouter.search_models(query) do
      {:ok, results} ->
        {:noreply,
         socket
         |> assign(:model_query, query)
         |> assign(:model_results, results)
         |> assign(:model_dropdown_open, true)}

      {:error, _} ->
        {:noreply, assign(socket, :model_dropdown_open, false)}
    end
  end

  def handle_event("select_model", %{"id" => model_id}, socket) do
    {:noreply,
     socket
     |> assign(:model_query, model_id)
     |> assign(:model_dropdown_open, false)
     |> assign(:model_results, [])}
  end

  def handle_event("open_model_dropdown", _, socket) do
    query = socket.assigns.model_query

    case Estimate.AI.OpenRouter.search_models(if(query == "", do: " ", else: query)) do
      {:ok, results} ->
        {:noreply,
         socket
         |> assign(:model_results, results)
         |> assign(:model_dropdown_open, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_model_dropdown", _, socket) do
    {:noreply, assign(socket, :model_dropdown_open, false)}
  end

  @impl true
  def handle_event("save_ai_settings", %{"ai" => ai_params}, socket) do
    unless admin?(socket.assigns.current_membership) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      # Don't overwrite key if left blank
      ai_params =
        if ai_params["openrouter_api_key"] == "" do
          Map.delete(ai_params, "openrouter_api_key")
        else
          ai_params
        end

      case Organizations.update_ai_settings(socket.assigns.current_organization, ai_params) do
        {:ok, org} ->
          ai_changeset = Estimate.Accounts.Organization.ai_settings_changeset(org, %{})

          {:noreply,
           socket
           |> put_flash(:info, "AI settings saved")
           |> assign(:current_organization, org)
           |> assign(:ai_form, to_form(ai_changeset, as: :ai))
           |> assign(:ai_configured, org.encrypted_openrouter_api_key != nil)
           |> assign(:ai_key_masked, Organizations.mask_api_key(org))
           |> assign(:model_query, org.openrouter_model || "")}

        {:error, changeset} ->
          {:noreply, assign(socket, ai_form: to_form(changeset, as: :ai))}
      end
    end
  end

  defp format_context(nil), do: ""
  defp format_context(n) when n >= 1_000_000, do: "#{div(n, 1_000_000)}M ctx"
  defp format_context(n) when n >= 1_000, do: "#{div(n, 1_000)}K ctx"
  defp format_context(n), do: "#{n} ctx"
end
