defmodule EstimateWeb.UserLive.ResetPassword do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <h1 class="text-3xl font-bold text-center text-base-content mb-8">
        Reset Password
      </h1>

      <form
        id="reset_password_form"
        phx-submit="reset_password"
        phx-change="validate"
        class="space-y-4"
      >
        <div
          :if={@form.errors != []}
          class="p-3 bg-error/10 border border-error/20 rounded-lg text-error text-sm"
        >
          Oops, something went wrong! Please check the errors below.
        </div>

        <.auth_input
          field={@form[:password]}
          type="password"
          placeholder="New password"
          required
        />

        <.auth_input
          field={@form[:password_confirmation]}
          type="password"
          placeholder="Confirm new password"
          required
        />

        <button
          type="submit"
          phx-disable-with="Resetting..."
          class="w-full py-3 px-4 bg-neutral text-neutral-content font-medium rounded-lg hover:bg-neutral/90 transition-colors"
        >
          Reset Password
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

  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} -> Accounts.change_user_password(user)
        _ -> %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, form: to_form(source, as: "user"))
  end
end
