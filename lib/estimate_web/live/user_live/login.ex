defmodule EstimateWeb.UserLive.Login do
  use EstimateWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <.auth_header title="Log in to EstiMate" />

      <form
        action={~p"/users/log_in"}
        method="post"
        class="space-y-4"
        id="login_form"
        phx-update="ignore"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input :if={@return_to} type="hidden" name="return_to" value={@return_to} />

        <.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />

        <.auth_input type="password" name="user[password]" placeholder="Password" required />

        <div class="flex items-center justify-between text-sm">
          <label class="flex items-center gap-2 cursor-pointer">
            <input type="checkbox" name="user[remember_me]" class="rounded border-base-content/20" />
            <span class="text-base-content/70">Remember me</span>
          </label>
          <.link href={~p"/users/reset_password"} class="text-base-content/70 hover:text-base-content">
            Forgot password?
          </.link>
        </div>

        <.auth_submit>Continue with Email</.auth_submit>
      </form>

      <.oauth_section href={
        if @return_to, do: ~p"/auth/google?#{%{return_to: @return_to}}", else: ~p"/auth/google"
      } />

      <p class="mt-8 text-center text-base-content/70">
        Don't have an account?
        <.link navigate={~p"/users/register"} class="text-info hover:text-info font-medium">
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
