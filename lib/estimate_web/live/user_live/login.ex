defmodule EstimateWeb.UserLive.Login do
  use EstimateWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <h1 class="text-3xl font-bold text-center text-gray-900 mb-8">
        Log in to EstiMate
      </h1>

      <form
        action={~p"/users/log_in"}
        method="post"
        class="space-y-4"
        id="login_form"
        phx-update="ignore"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input :if={@return_to} type="hidden" name="return_to" value={@return_to} />

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

        <div>
          <input
            type="password"
            name="user[password]"
            placeholder="Password"
            required
            class="w-full px-4 py-3 border border-gray-300 rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
          />
        </div>

        <div class="flex items-center justify-between text-sm">
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" name="user[remember_me]" class="rounded border-gray-300" />
            <span class="text-gray-600">Remember me</span>
          </label>
          <.link href={~p"/users/reset_password"} class="text-gray-600 hover:text-gray-900">
            Forgot password?
          </.link>
        </div>

        <button
          type="submit"
          class="w-full py-3 px-4 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors"
        >
          Continue with Email
        </button>
      </form>

      <.or_divider />

      <div class="space-y-3">
        <.google_button href={if @return_to, do: ~p"/auth/google?#{%{return_to: @return_to}}", else: ~p"/auth/google"} />
      </div>

      <p class="mt-8 text-center text-gray-600">
        Don't have an account?
        <.link navigate={~p"/users/register"} class="text-blue-600 hover:text-blue-700 font-medium">
          Sign Up
        </.link>
      </p>
    </div>
    """
  end

  def mount(params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    return_to = EstimateWeb.UserAuth.safe_return_to(params["return_to"])
    {:ok, assign(socket, form: form, return_to: return_to), temporary_assigns: [form: form]}
  end
end
