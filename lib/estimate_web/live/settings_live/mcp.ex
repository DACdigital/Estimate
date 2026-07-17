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
            <p
              :if={@current_organization.mcp_enabled}
              class="mt-2 text-sm font-mono text-base-content/70"
            >
              {@mcp_url}
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
        class="bg-base-100 border border-base-300 rounded-xl p-6"
      >
        <div class="mb-6 p-4 bg-base-200/60 rounded-lg">
          <h3 class="text-sm font-medium text-base-content mb-1">Connect from claude.ai</h3>
          <p class="text-sm text-base-content/60 mb-2">
            Add a custom connector with this URL — you'll sign in and pick this organization. No key needed.
          </p>
          <code class="block font-mono text-sm select-all">{@mcp_url}</code>
        </div>

        <h2 class="text-sm font-medium text-base-content mb-1">Your API key</h2>
        <p class="text-sm text-base-content/60 mb-4">
          The key acts as you: it sees exactly what you see in the app.
        </p>

        <div :if={@new_key} class="mb-4 p-4 bg-warning/10 border border-warning/30 rounded-lg">
          <p class="text-sm font-medium text-base-content mb-2">
            Copy your key now — it will not be shown again.
          </p>
          <code class="block font-mono text-sm break-all select-all mb-3">{@new_key}</code>
          <p class="text-xs font-medium text-base-content/60 mb-1">Add to Claude Code:</p>
          <code class="block font-mono text-xs break-all select-all mb-3">
            claude mcp add --transport http estimate {@mcp_url} --header "Authorization: Bearer {@new_key}"
          </code>
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
