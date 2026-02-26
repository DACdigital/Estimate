defmodule EstimateWeb.SettingsLive.Ai do
  use EstimateWeb, :live_view

  alias Estimate.Organizations
  import EstimateWeb.LiveHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">AI Integration</h1>
        <p class="mt-1 text-base-content/60">Connect to OpenRouter to enhance descriptions with AI</p>
      </div>

      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <.form for={@ai_form} id="ai-settings-form" phx-submit="save_ai_settings">
          <div class="p-6 flex gap-6">
            <div class="space-y-4 max-w-md flex-1">
              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  API Key
                  <span
                    :if={@ai_configured}
                    class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-success/10 text-success rounded-full"
                  >
                    <svg class="w-2.5 h-2.5" fill="currentColor" viewBox="0 0 8 8">
                      <circle cx="4" cy="4" r="4" />
                    </svg>
                    Connected · {@ai_key_masked}
                  </span>
                </label>
                <input
                  type="password"
                  name="ai[openrouter_api_key]"
                  placeholder={if @ai_configured, do: "Paste new key to replace", else: "sk-or-..."}
                  autocomplete="off"
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
                />
              </div>
              <div class="relative" phx-click-away="close_model_dropdown">
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">Model</label>
                <input
                  type="text"
                  name="ai[openrouter_model]"
                  value={@model_query}
                  phx-keyup="search_models"
                  phx-debounce="300"
                  phx-focus="open_model_dropdown"
                  placeholder="Search models..."
                  autocomplete="off"
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
                />
                <div
                  :if={@model_dropdown_open && @model_results != []}
                  class="absolute z-10 mt-1 w-full bg-base-100 border border-base-300 rounded-lg shadow-lg max-h-60 overflow-y-auto"
                >
                  <button
                    :for={model <- @model_results}
                    type="button"
                    phx-click="select_model"
                    phx-value-id={model.id}
                    class="w-full text-left px-3 py-2 hover:bg-base-200 border-b border-base-content/10 last:border-0"
                  >
                    <div class="text-sm font-medium text-base-content">{model.name || model.id}</div>
                    <div class="text-xs text-base-content/60">
                      {model.id} · {format_context(model.context_length)}
                    </div>
                  </button>
                </div>
              </div>
              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  System Prompt <span class="text-base-content/40">(optional)</span>
                </label>
                <textarea
                  name="ai[openrouter_system_prompt]"
                  rows="3"
                  placeholder="Default: enhance description for estimation..."
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm resize-none"
                ><%= @ai_form[:openrouter_system_prompt].value %></textarea>
              </div>
            </div>
            <div
              :if={@ai_configured && !(@ai_balance.ok? && is_nil(@ai_balance.result))}
              class="hidden sm:block"
            >
              <div :if={@ai_balance.loading} class="animate-pulse text-sm text-base-content/40 mt-5">
                ...
              </div>
              <div :if={@ai_balance.ok? && @ai_balance.result}>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  Current Usage
                </label>
                <div class="font-mono text-2xl font-medium text-base-content/80 leading-10">
                  ${format_usd(@ai_balance.result.usage)}
                </div>
              </div>
            </div>
          </div>
          <div class="px-6 py-3 bg-base-100 border-t border-base-300 flex items-center justify-between">
            <p class="text-sm text-base-content/60">API key is encrypted at rest.</p>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
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
       |> assign(:model_dropdown_open, false)
       |> maybe_fetch_balance(org)}
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
    require_admin(socket, fn ->
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
           |> assign(:model_query, org.openrouter_model || "")
           |> maybe_fetch_balance(org)}

        {:error, changeset} ->
          {:noreply, assign(socket, ai_form: to_form(changeset, as: :ai))}
      end
    end)
  end

  defp maybe_fetch_balance(socket, org) do
    if org.encrypted_openrouter_api_key do
      assign_async(socket, :ai_balance, fn ->
        api_key = Organizations.get_decrypted_api_key(org)

        case Estimate.AI.OpenRouter.get_key_info(api_key) do
          {:ok, info} -> {:ok, %{ai_balance: info}}
          {:error, _} -> {:ok, %{ai_balance: nil}}
        end
      end)
    else
      assign(socket, :ai_balance, %Phoenix.LiveView.AsyncResult{ok?: true, result: nil})
    end
  end

  defp format_usd(nil), do: "0.0000"
  defp format_usd(n), do: :erlang.float_to_binary(n / 1, decimals: 4)

  defp format_context(nil), do: ""
  defp format_context(n) when n >= 1_000_000, do: "#{div(n, 1_000_000)}M ctx"
  defp format_context(n) when n >= 1_000, do: "#{div(n, 1_000)}K ctx"
  defp format_context(n), do: "#{n} ctx"
end
