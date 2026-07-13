defmodule EstimateWeb.UserLive.ForgotPassword do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <.auth_header title="Forgot your password?">
        <:subtitle>We'll send a password reset link to your inbox</:subtitle>
      </.auth_header>

      <form id="reset_password_form" phx-submit="send_email" class="space-y-4">
        <.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />

        <.auth_submit loading="Sending...">Send reset link</.auth_submit>
      </form>

      <p class="mt-8 text-center text-base-content/70">
        <.link navigate={~p"/users/register"} class="text-info hover:text-info font-medium">
          Sign Up
        </.link>
        <span class="mx-2 text-base-content/30">|</span>
        <.link navigate={~p"/users/log_in"} class="text-info hover:text-info font-medium">
          Sign In
        </.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
