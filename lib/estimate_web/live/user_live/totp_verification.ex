defmodule EstimateWeb.UserLive.TotpVerification do
  use EstimateWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full">
      <.auth_header title="Two-Factor Authentication">
        <:subtitle>Enter the code from your authenticator app</:subtitle>
      </.auth_header>

      <form
        action={~p"/users/two-factor/verify"}
        method="post"
        class="space-y-4"
        id="totp_form"
        phx-update="ignore"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

        <%= if @use_backup do %>
          <.auth_input
            name="code"
            type="text"
            placeholder="Backup code"
            class="font-mono"
            autocomplete="one-time-code"
            autofocus
          />
        <% else %>
          <.auth_input
            name="code"
            type="text"
            placeholder="000000"
            class="text-center font-mono text-lg tracking-[0.5em]"
            maxlength="6"
            inputmode="numeric"
            autocomplete="one-time-code"
            autofocus
          />
        <% end %>

        <.auth_submit>Verify</.auth_submit>
      </form>

      <div class="mt-6 text-center">
        <button
          phx-click="toggle_backup"
          class="text-sm text-base-content/60 hover:text-base-content transition-colors"
        >
          {if @use_backup, do: "Use authenticator code", else: "Use a backup code"}
        </button>
      </div>

      <p class="mt-8 text-center">
        <.link
          navigate={~p"/users/log_in"}
          class="text-sm text-base-content/60 hover:text-base-content"
        >
          Back to login
        </.link>
      </p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Two-Factor Authentication")
     |> assign(:use_backup, false)}
  end

  @impl true
  def handle_event("toggle_backup", _params, socket) do
    {:noreply, assign(socket, :use_backup, !socket.assigns.use_backup)}
  end
end
