defmodule EstimateWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]
  import EstimateWeb.AuthHelpers

  def require_admin(socket, fun) do
    if admin?(socket.assigns.current_membership),
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "Not authorized")}
  end
end
