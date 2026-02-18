defmodule EstimateWeb.EstimatorLive.Components.EstimateCell do
  use EstimateWeb, :html

  alias Estimate.EstimationEngine.Calculator
  import EstimateWeb.EstimatorLive.Helpers

  attr :task_id, :string, required: true
  attr :role_id, :string, required: true
  attr :estimates, :list, required: true
  attr :editing, :map, required: true

  def estimate_cell(assigns) do
    estimate = Enum.find(assigns.estimates, &(&1.estimation_role_id == assigns.role_id))
    hours = if estimate, do: estimate.hours, else: Decimal.new(0)

    editing_key = "#{assigns.task_id}-#{assigns.role_id}"
    is_editing = assigns.editing == editing_key

    assigns =
      assigns
      |> assign(:hours, hours)
      |> assign(:is_editing, is_editing)
      |> assign(:editing_key, editing_key)

    ~H"""
    <%= if @is_editing do %>
      <input
        type="number"
        step="0.5"
        min="0"
        value={if Decimal.compare(@hours, 0) == :eq, do: "", else: @hours}
        placeholder="0"
        phx-blur="save_estimate"
        phx-keydown="save_estimate"
        phx-key="Enter"
        phx-value-task-id={@task_id}
        phx-value-role-id={@role_id}
        phx-mounted={JS.focus()}
        class="w-16 h-8 text-center text-sm font-mono rounded bg-emerald-50 text-emerald-900 focus:outline-none"
        id={"hours-#{@editing_key}"}
      />
    <% else %>
      <button
        phx-click="edit_estimate"
        phx-value-key={@editing_key}
        class={"w-16 h-8 inline-flex items-center justify-center align-middle text-sm font-mono rounded cursor-pointer transition-colors #{if Decimal.compare(@hours, 0) == :eq, do: "text-gray-400 hover:bg-gray-50 hover:text-gray-500", else: "text-gray-900 bg-gray-50 hover:bg-gray-100"}"}
      >
        {format_hours(@hours)}
      </button>
    <% end %>
    """
  end

  attr :role, :map, required: true
  attr :currency, :map, required: true
  attr :editing_rate, :string, required: true
  attr :show_all_in_rates, :boolean, required: true

  def rate_cell(assigns) do
    is_editing = assigns.editing_rate == assigns.role.id

    display_rate =
      if assigns.show_all_in_rates do
        Calculator.all_in_rate(assigns.role)
      else
        assigns.role.hourly_rate
      end

    assigns =
      assigns
      |> assign(:is_editing, is_editing)
      |> assign(:display_rate, display_rate)

    ~H"""
    <%= if @is_editing do %>
      <input
        type="number"
        step="1"
        min="0"
        value={@role.hourly_rate}
        phx-blur="save_rate"
        phx-keydown="save_rate"
        phx-key="Enter"
        phx-value-role-id={@role.id}
        class="w-12 text-center text-[10px] font-mono border border-gray-400 rounded bg-white focus:outline-none focus:border-gray-900"
        id={"rate-#{@role.id}"}
        autofocus
      />
    <% else %>
      <button
        phx-click="edit_rate"
        phx-value-role-id={@role.id}
        class={"text-[10px] font-mono font-normal normal-case hover:text-gray-600 cursor-pointer #{if @show_all_in_rates, do: "text-emerald-600", else: "text-gray-400"}"}
      >
        {format_rate(@display_rate, @currency)}
      </button>
    <% end %>
    """
  end
end
