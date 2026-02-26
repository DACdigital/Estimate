defmodule EstimateWeb.UserLive.TotpSetup do
  use EstimateWeb, :live_view

  alias Estimate.Accounts.Totp
  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Set Up Two-Factor Authentication</h1>
        <p class="mt-1 text-base-content/60">
          <%= case @step do %>
            <% :qr -> %>
              Step 1 of 3 — Scan QR code
            <% :verify -> %>
              Step 2 of 3 — Verify code
            <% :backup -> %>
              Step 3 of 3 — Save backup codes
          <% end %>
        </p>
      </div>
      
    <!-- Progress bar -->
      <div class="flex gap-2 mb-8">
        <div class={[
          "h-1 flex-1 rounded-full",
          if(@step in [:qr, :verify, :backup], do: "bg-neutral", else: "bg-base-300")
        ]} />
        <div class={[
          "h-1 flex-1 rounded-full",
          if(@step in [:verify, :backup], do: "bg-neutral", else: "bg-base-300")
        ]} />
        <div class={[
          "h-1 flex-1 rounded-full",
          if(@step == :backup, do: "bg-neutral", else: "bg-base-300")
        ]} />
      </div>

      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <%= case @step do %>
          <% :qr -> %>
            <.step_qr qr_svg={@qr_svg} manual_key={@manual_key} />
          <% :verify -> %>
            <.step_verify error={@verify_error} />
          <% :backup -> %>
            <.step_backup backup_codes={@backup_codes} saved_confirmed={@saved_confirmed} />
        <% end %>
      </div>
    </div>
    """
  end

  defp step_qr(assigns) do
    ~H"""
    <div class="p-6">
      <p class="text-sm text-base-content/70 mb-6">
        Scan this QR code with your authenticator app (Google Authenticator, Authy, 1Password, etc.)
      </p>

      <div class="flex justify-center mb-6">
        <div class="p-4 bg-white rounded-xl">
          {Phoenix.HTML.raw(@qr_svg)}
        </div>
      </div>

      <details class="text-sm">
        <summary class="cursor-pointer text-base-content/60 hover:text-base-content transition-colors">
          Can't scan? Enter key manually
        </summary>
        <div class="mt-3 p-3 bg-base-200 rounded-lg flex items-center justify-between gap-3">
          <code class="text-sm font-mono break-all select-all">{@manual_key}</code>
          <button
            type="button"
            phx-click="copy_manual_key"
            class="shrink-0 text-xs px-2.5 py-1 border border-base-300 rounded-md text-base-content/60 hover:text-base-content hover:bg-base-300 transition-colors"
          >
            Copy
          </button>
        </div>
      </details>
    </div>
    <div class="px-6 py-3 bg-base-100 border-t border-base-300 flex justify-end">
      <button
        phx-click="next_to_verify"
        class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
      >
        Next
      </button>
    </div>
    """
  end

  defp step_verify(assigns) do
    ~H"""
    <div class="p-6">
      <p class="text-sm text-base-content/70 mb-6">
        Enter the 6-digit code from your authenticator app to verify setup.
      </p>

      <form phx-submit="verify_code" class="space-y-4">
        <div>
          <input
            type="text"
            name="code"
            placeholder="000000"
            maxlength="6"
            autocomplete="one-time-code"
            inputmode="numeric"
            autofocus
            class={[
              "w-full px-4 py-3 border rounded-lg text-lg font-mono tracking-[0.5em] text-center",
              @error && "border-error",
              !@error && "border-base-content/20"
            ]}
          />
          <p :if={@error} class="mt-2 text-sm text-error">{@error}</p>
        </div>
        <button
          type="submit"
          phx-disable-with="Verifying..."
          class="w-full py-3 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
        >
          Verify & Enable
        </button>
      </form>
    </div>
    """
  end

  defp step_backup(assigns) do
    ~H"""
    <div class="p-6">
      <p class="text-sm text-base-content/70 mb-6">
        Save these backup codes in a safe place. Each code can only be used once if you lose access to your authenticator app.
      </p>

      <div class="grid grid-cols-2 gap-2 mb-6">
        <div
          :for={code <- @backup_codes}
          class="px-3 py-2 bg-base-200 rounded-lg font-mono text-sm text-center select-all"
        >
          {code}
        </div>
      </div>

      <label class="flex items-center gap-2 cursor-pointer mb-4">
        <input
          type="checkbox"
          phx-click="toggle_saved"
          checked={@saved_confirmed}
          class="rounded border-base-content/20"
        />
        <span class="text-sm text-base-content/70">I've saved these codes in a safe place</span>
      </label>
    </div>
    <div class="px-6 py-3 bg-base-100 border-t border-base-300 flex justify-end">
      <button
        phx-click="finish_setup"
        disabled={!@saved_confirmed}
        class={[
          "px-4 py-2 text-sm rounded-lg transition-colors font-medium",
          @saved_confirmed && "bg-neutral text-neutral-content hover:bg-neutral/90",
          !@saved_confirmed && "bg-base-300 text-base-content/40 cursor-not-allowed"
        ]}
      >
        Done
      </button>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    secret = Totp.generate_secret()
    uri = Totp.generate_otpauth_uri(user.email, secret)
    qr_svg = Totp.generate_qr_svg(uri)
    manual_key = Base.encode32(secret, padding: false)

    {:ok,
     socket
     |> assign(:page_title, "Set Up 2FA")
     |> assign(:settings_page, :security)
     |> assign(:step, :qr)
     |> assign(:secret, secret)
     |> assign(:qr_svg, qr_svg)
     |> assign(:manual_key, manual_key)
     |> assign(:verify_error, nil)
     |> assign(:backup_codes, [])
     |> assign(:saved_confirmed, false)}
  end

  @impl true
  def handle_event("copy_manual_key", _params, socket) do
    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: socket.assigns.manual_key})
     |> put_flash(:info, "Key copied to clipboard")}
  end

  def handle_event("next_to_verify", _params, socket) do
    {:noreply, assign(socket, :step, :verify)}
  end

  def handle_event("verify_code", %{"code" => code}, socket) do
    code = String.trim(code)

    if Totp.valid_code?(socket.assigns.secret, code) do
      user = socket.assigns.current_user
      secret = socket.assigns.secret
      {plain_codes, hashed_codes} = Totp.generate_backup_codes()

      case Totp.enable_totp(user, secret, hashed_codes) do
        {:ok, _user} ->
          # Clear 2FA deadlines across all orgs
          Organizations.clear_2fa_deadlines_for_user(user.id)

          {:noreply,
           socket
           |> assign(:step, :backup)
           |> assign(:backup_codes, plain_codes)}

        {:error, _} ->
          {:noreply, assign(socket, :verify_error, "Failed to enable 2FA. Try again.")}
      end
    else
      {:noreply,
       assign(socket, :verify_error, "Invalid code. Check your authenticator app and try again.")}
    end
  end

  def handle_event("toggle_saved", _params, socket) do
    {:noreply, assign(socket, :saved_confirmed, !socket.assigns.saved_confirmed)}
  end

  def handle_event("finish_setup", _params, socket) do
    if socket.assigns.saved_confirmed do
      {:noreply,
       socket
       |> put_flash(:info, "Two-factor authentication enabled!")
       |> push_navigate(to: ~p"/account")}
    else
      {:noreply, socket}
    end
  end
end
