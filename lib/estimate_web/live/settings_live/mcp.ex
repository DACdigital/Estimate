defmodule EstimateWeb.SettingsLive.Mcp do
  use EstimateWeb, :live_view

  alias Estimate.MCP
  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">MCP Server</h1>
        <p class="mt-1 text-base-content/60">
          Expose read-only org data to MCP clients (Claude Code, Claude Desktop, Cursor…)
        </p>
      </div>

      <div
        :if={admin?(@current_membership)}
        id="mcp-server-card"
        class="bg-base-100 border border-base-300 rounded-xl p-6 mb-6"
      >
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-sm font-medium text-base-content">
              {if @current_organization.mcp_enabled,
                do: "MCP server is enabled",
                else: "MCP server is disabled"}
            </h2>
            <p class="mt-1 text-sm text-base-content/60">
              Members authenticate with personal API keys that inherit their access. Disabling
              instantly rejects every key.
            </p>
          </div>
          <button
            phx-click="toggle_mcp"
            class={[
              "px-4 py-1.5 text-sm rounded-md font-medium transition-colors",
              if(@current_organization.mcp_enabled,
                do: "bg-error/10 text-error hover:bg-error/20",
                else: "bg-neutral text-neutral-content hover:bg-neutral/90"
              )
            ]}
          >
            {if @current_organization.mcp_enabled, do: "Disable", else: "Enable"}
          </button>
        </div>
      </div>

      <div
        :if={!@current_organization.mcp_enabled && !admin?(@current_membership)}
        class="bg-base-100 border border-base-300 rounded-xl p-6"
      >
        <p class="text-sm text-base-content/60">
          The MCP server is disabled for this organization. Ask an admin to enable it.
        </p>
      </div>

      <div
        :if={@current_organization.mcp_enabled}
        id="mcp-claude-ai"
        class="bg-base-100 border border-base-300 rounded-xl p-6 mb-6"
      >
        <h2 class="text-sm font-medium text-base-content">Connect from claude.ai</h2>
        <p class="mt-1 text-sm text-base-content/60 mb-3">
          Add a custom connector with this URL — you'll sign in and pick this organization. No key needed.
        </p>
        <div class="flex items-start gap-2">
          <code
            class="flex-1 block font-mono text-sm bg-base-200/60 rounded-lg p-3 select-all"
            phx-no-format
          >{@mcp_url}</code>
          <.copy_button what="url" />
        </div>
      </div>

      <div
        :if={@current_organization.mcp_enabled}
        id="mcp-api-clients"
        class="bg-base-100 border border-base-300 rounded-xl p-6"
      >
        <h2 class="text-sm font-medium text-base-content">API clients</h2>
        <p class="mt-1 text-sm text-base-content/60 mb-4">
          Claude Code, Claude Desktop, Cursor — authenticate with your personal key.
          The key acts as you: it sees exactly what you see in the app.
        </p>

        <div :if={@new_key} class="mb-4 p-4 bg-warning/10 border border-warning/30 rounded-lg">
          <p class="text-sm font-medium text-base-content mb-2">
            Copy your key now — it will not be shown again.
          </p>
          <div class="flex items-start gap-2 mb-3">
            <code class="flex-1 block font-mono text-sm break-all select-all">{@new_key}</code>
            <.copy_button what="key" />
          </div>
          <button
            phx-click="dismiss_new_key"
            class="text-sm text-base-content/60 hover:text-base-content"
          >
            Dismiss
          </button>
        </div>

        <div :if={@api_key} class="flex items-center justify-between">
          <div class="text-sm text-base-content/70 font-mono">
            {@api_key.key_prefix}…
            <span class="ml-3 font-sans text-base-content/50">
              created {Calendar.strftime(@api_key.inserted_at, "%Y-%m-%d")}
            </span>
            <span :if={@api_key.last_used_at} class="ml-3 font-sans text-base-content/50">
              last used {Calendar.strftime(@api_key.last_used_at, "%Y-%m-%d %H:%M")} UTC
            </span>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="generate_key"
              data-confirm="This invalidates your current key. Continue?"
              class="px-3 py-1.5 text-sm rounded-md border border-base-300 hover:bg-base-200 transition-colors"
            >
              Regenerate
            </button>
            <button
              phx-click="revoke_key"
              data-confirm="Revoke your API key?"
              class="px-3 py-1.5 text-sm rounded-md text-error hover:bg-error/10 transition-colors"
            >
              Revoke
            </button>
          </div>
        </div>

        <button
          :if={@api_key == nil}
          phx-click="generate_key"
          class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
        >
          Generate API Key
        </button>

        <div id="mcp-setup-snippets" class="mt-6 pt-6 border-t border-base-300">
          <h3 class="text-sm font-medium text-base-content mb-1">Setup</h3>
          <p :if={@new_key == nil} class="text-sm text-base-content/60 mb-3">
            <code class="font-mono text-xs">est_YOUR_KEY</code>
            is a placeholder — generate or regenerate a key to fill it in.
          </p>
          <p :if={@new_key} class="text-sm text-base-content/60 mb-3">
            Snippets below include your new key.
          </p>
          <.snippet
            label="Claude Code"
            text={cli_snippet(@mcp_url, display_key(@new_key))}
            what="cli"
          />
          <.snippet
            label="Claude Desktop / Cursor / .mcp.json"
            text={json_snippet(@mcp_url, display_key(@new_key))}
            what="json"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :what, :string, required: true

  defp copy_button(assigns) do
    ~H"""
    <button
      phx-click="copy"
      phx-value-what={@what}
      class="shrink-0 text-base-content/40 hover:text-base-content/70 transition-colors"
      aria-label="Copy to clipboard"
      title="Copy"
    >
      <.icon name="hero-clipboard-document" class="w-4 h-4" />
    </button>
    """
  end

  attr :label, :string, required: true
  attr :text, :string, required: true
  attr :what, :string, required: true

  defp snippet(assigns) do
    ~H"""
    <div class="mb-4 last:mb-0">
      <div class="text-xs font-medium text-base-content/60 mb-1">{@label}</div>
      <div class="flex items-start gap-2">
        <code
          class="flex-1 block font-mono text-xs bg-base-200/60 rounded-lg p-3 break-all whitespace-pre-wrap select-all"
          phx-no-format
        >{@text}</code>
        <.copy_button what={@what} />
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, org_id: org_id} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "MCP Server")
     |> assign(:active_tab, :settings)
     |> assign(:settings_page, :mcp)
     |> assign(:mcp_url, url(~p"/mcp"))
     |> assign(:api_key, MCP.get_api_key(user.id, org_id))
     |> assign(:new_key, nil)}
  end

  @impl true
  def handle_event("toggle_mcp", _params, socket) do
    require_admin(socket, fn ->
      org = socket.assigns.current_organization

      case Organizations.update_mcp_settings(org, %{mcp_enabled: !org.mcp_enabled}) do
        {:ok, org} ->
          {:noreply,
           socket
           |> assign(:current_organization, org)
           |> assign(:new_key, nil)
           |> put_flash(
             :info,
             if(org.mcp_enabled, do: "MCP server enabled", else: "MCP server disabled")
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update MCP settings")}
      end
    end)
  end

  @impl true
  def handle_event("generate_key", _params, socket) do
    require_mcp_enabled(socket, fn ->
      %{current_user: user, org_id: org_id} = socket.assigns

      case MCP.generate_api_key(user.id, org_id) do
        {:ok, {plaintext, api_key}} ->
          {:noreply, socket |> assign(:api_key, api_key) |> assign(:new_key, plaintext)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not generate API key")}
      end
    end)
  end

  @impl true
  def handle_event("revoke_key", _params, socket) do
    require_mcp_enabled(socket, fn ->
      %{current_user: user, org_id: org_id} = socket.assigns
      MCP.revoke_api_key(user.id, org_id)

      {:noreply,
       socket
       |> assign(:api_key, nil)
       |> assign(:new_key, nil)
       |> put_flash(:info, "API key revoked")}
    end)
  end

  @impl true
  def handle_event("dismiss_new_key", _params, socket) do
    {:noreply, assign(socket, :new_key, nil)}
  end

  @impl true
  def handle_event("copy", %{"what" => what}, socket) do
    case copy_text(what, socket.assigns) do
      nil ->
        {:noreply, socket}

      text ->
        {:noreply,
         socket
         |> push_event("copy_to_clipboard", %{text: text})
         |> put_flash(:info, "Copied to clipboard")}
    end
  end

  @placeholder_key "est_YOUR_KEY"

  # Copy payloads are recomputed from assigns — the client only names a target.
  defp copy_text("url", %{mcp_url: url}), do: url
  defp copy_text("key", %{new_key: key}), do: key
  defp copy_text("cli", %{mcp_url: url, new_key: key}), do: cli_snippet(url, display_key(key))
  defp copy_text("json", %{mcp_url: url, new_key: key}), do: json_snippet(url, display_key(key))
  defp copy_text(_, _), do: nil

  defp display_key(nil), do: @placeholder_key
  defp display_key(key), do: key

  defp cli_snippet(url, key) do
    ~s(claude mcp add --transport http estimate #{url} --header "Authorization: Bearer #{key}")
  end

  defp json_snippet(url, key) do
    Jason.encode!(
      %{
        "mcpServers" => %{
          "estimate" => %{
            "type" => "http",
            "url" => url,
            "headers" => %{"Authorization" => "Bearer " <> key}
          }
        }
      },
      pretty: true
    )
  end

  # `current_organization` is a mount-time snapshot, so it can lag a concurrent
  # admin's toggle within the same connection's lifetime; acceptable here since
  # verify_api_key/1 is the authoritative gate at actual MCP request time — this
  # guard only blocks wasted/forged writes from a stale-but-disabled UI.
  defp require_mcp_enabled(socket, fun) do
    if socket.assigns.current_organization.mcp_enabled,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "MCP is disabled for this organization")}
  end
end
