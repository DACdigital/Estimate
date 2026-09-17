defmodule EstimateWeb.EstimatorLive.AI do
  @moduledoc """
  AI description enhancement: kicks off `start_async/3` against the configured
  provider (seam: `Application.get_env(:estimate, :ai_enhancer, Estimate.AI.OpenRouter)`)
  and handles the async result.

  Reads: `:current_organization`, `:can_edit` (via Authz).
  Writes: `:ai_loading`, flash; pushes `ai_set_description`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  alias Estimate.Organizations

  def enhance_description(socket, %{"description" => desc, "name" => name, "target" => target}) do
    with_edit_auth(socket, fn socket ->
      org = socket.assigns.current_organization
      api_key = Organizations.get_decrypted_api_key(org)

      if api_key do
        model = org.openrouter_model || "openai/gpt-4o-mini"
        system_prompt = org.openrouter_system_prompt
        enhancer = Application.get_env(:estimate, :ai_enhancer, Estimate.AI.OpenRouter)

        {:noreply,
         socket
         |> assign(:ai_loading, target)
         |> start_async({:ai_enhance, target}, fn ->
           enhancer.enhance_description(api_key, model, system_prompt, name, desc)
         end)}
      else
        {:noreply, put_flash(socket, :error, "AI not configured")}
      end
    end)
  end

  def handle_result(target, {:ok, {:ok, enhanced}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> push_event("ai_set_description", %{text: enhanced, target: target})}
  end

  def handle_result(_target, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> put_flash(:error, "AI error: #{reason}")}
  end

  def handle_result(_target, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> put_flash(:error, "AI request failed")}
  end
end
