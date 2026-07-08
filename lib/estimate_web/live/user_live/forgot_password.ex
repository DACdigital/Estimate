defmodule EstimateWeb.UserLive.ForgotPassword do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <h1 class="text-3xl font-bold text-center text-base-content mb-2">
        Forgot your password?
      </h1>
      <p class="text-center text-base-content/60 mb-8">
        We'll send a password reset link to your inbox
      </p>

      <form id="reset_password_form" phx-submit="send_email" class="space-y-4">
        <.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />

        <button
          type="submit"
          phx-disable-with="Sending..."
          class="w-full py-3 px-4 bg-neutral text-neutral-content font-medium rounded-lg hover:bg-neutral/90 transition-colors"
        >
          Send reset link
        </button>
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
