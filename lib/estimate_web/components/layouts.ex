defmodule EstimateWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EstimateWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  defp days_remaining(deadline) do
    days = DateTime.diff(deadline, DateTime.utc_now(), :day)

    cond do
      days <= 0 -> "less than a day"
      days == 1 -> "1 day"
      true -> "#{days} days"
    end
  end

  @doc """
  Sidebar navigation link component.
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def sidebar_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors",
        @active && "bg-base-200 text-base-content",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="w-5 h-5" />
      <span>{@label}</span>
    </a>
    """
  end

  @doc """
  Sidebar child link (no icon, indented under a group header).
  Pass `navigate` (instead of `href`) for LiveView live navigation.
  """
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def sidebar_child_link(assigns) do
    ~H"""
    <.link
      href={@href}
      navigate={@navigate}
      class={[
        "block px-3 py-1.5 rounded-lg text-sm transition-colors",
        @active && "bg-base-200 text-base-content font-medium",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      {@label}
    </.link>
    """
  end

  @doc """
  Secondary navigation rail for the settings area.

  Rendered by the app layout whenever the LiveView assigned `:settings_page`.
  The stable DOM id lets morphdom persist the element across settings-to-settings
  live navigations, so the entry animation plays only when settings is entered.
  """
  attr :org_id, :string, required: true
  attr :settings_page, :atom, required: true
  attr :current_membership, :map, required: true

  def settings_rail(assigns) do
    ~H"""
    <aside
      id="settings-rail"
      class="settings-rail-enter w-52 shrink-0 border-r border-base-300 bg-base-100 px-4 py-6 overflow-y-auto"
    >
      <div class="px-3 pb-1.5 text-xs font-semibold uppercase tracking-wider text-base-content/40">
        Workspace
      </div>
      <div class="space-y-0.5">
        <.sidebar_child_link
          navigate={~p"/org/#{@org_id}/settings"}
          label="General"
          active={@settings_page == :general}
        />
        <.sidebar_child_link
          navigate={~p"/org/#{@org_id}/settings/members"}
          label="Members"
          active={@settings_page == :members}
        />
        <.sidebar_child_link
          navigate={~p"/org/#{@org_id}/settings/currencies"}
          label="Currencies"
          active={@settings_page == :currencies}
        />
        <.sidebar_child_link
          :if={admin?(@current_membership)}
          navigate={~p"/org/#{@org_id}/settings/trash"}
          label="Trash"
          active={@settings_page == :trash}
        />
      </div>

      <div class="px-3 pb-1.5 pt-6 text-xs font-semibold uppercase tracking-wider text-base-content/40">
        Integrations
      </div>
      <div class="space-y-0.5">
        <.sidebar_child_link
          :if={admin?(@current_membership)}
          navigate={~p"/org/#{@org_id}/settings/ai"}
          label="AI"
          active={@settings_page == :ai}
        />
        <.sidebar_child_link
          :if={admin?(@current_membership)}
          navigate={~p"/org/#{@org_id}/settings/email"}
          label="Email"
          active={@settings_page == :email}
        />
        <.sidebar_child_link
          navigate={~p"/org/#{@org_id}/settings/mcp"}
          label="MCP"
          active={@settings_page == :mcp}
        />
      </div>
    </aside>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
