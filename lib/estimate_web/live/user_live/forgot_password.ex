defmodule EstimateWeb.UserLive.ForgotPassword do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <h1 class="text-3xl font-bold text-center text-gray-900 mb-2">
        Forgot your password?
      </h1>
      <p class="text-center text-gray-500 mb-8">
        We'll send a password reset link to your inbox
      </p>

      <form id="reset_password_form" phx-submit="send_email" class="space-y-4">
        <div>
          <input
            type="email"
            name="user[email]"
            value={@form[:email].value}
            placeholder="Email Address"
            required
            class="w-full px-4 py-3 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
          />
        </div>

        <button
          type="submit"
          phx-disable-with="Sending..."
          class="w-full py-3 px-4 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors"
        >
          Send reset link
        </button>
      </form>

      <p class="mt-8 text-center text-gray-600">
        <.link navigate={~p"/users/register"} class="text-blue-600 hover:text-blue-700 font-medium">
          Sign Up
        </.link>
        <span class="mx-2 text-gray-300">|</span>
        <.link navigate={~p"/users/log_in"} class="text-blue-600 hover:text-blue-700 font-medium">
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
