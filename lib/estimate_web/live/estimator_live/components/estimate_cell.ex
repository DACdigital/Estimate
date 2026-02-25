defmodule EstimateWeb.EstimatorLive.Components.EstimateCell do
  use EstimateWeb, :html

  alias Estimate.EstimationEngine.Calculator
  import EstimateWeb.EstimatorLive.Helpers

  attr :task_id, :string, required: true
  attr :role_id, :string, required: true
  attr :estimates, :list, required: true
  attr :editing, :map, required: true
  attr :can_edit, :boolean, default: true

  def estimate_cell(assigns) do
    estimate = Enum.find(assigns.estimates, &(&1.estimation_role_id == assigns.role_id))
    hours = if estimate, do: estimate.hours, else: Decimal.new(0)

    editing_key = "#{assigns.task_id}-#{assigns.role_id}"
    is_editing = assigns.can_edit and assigns.editing == editing_key

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
      <%= if @can_edit do %>
        <button
          phx-click="edit_estimate"
          phx-value-key={@editing_key}
          class={"w-16 h-8 inline-flex items-center justify-center align-middle text-sm font-mono rounded cursor-pointer transition-colors #{if Decimal.compare(@hours, 0) == :eq, do: "text-base-content/40 hover:bg-base-200 hover:text-base-content/60", else: "text-base-content bg-base-200 hover:bg-base-300"}"}
        >
          {format_hours(@hours)}
        </button>
      <% else %>
        <span class={"w-16 h-8 inline-flex items-center justify-center align-middle text-sm font-mono #{if Decimal.compare(@hours, 0) == :eq, do: "text-base-content/40", else: "text-base-content"}"}>
          {format_hours(@hours)}
        </span>
      <% end %>
    <% end %>
    """
  end

  attr :role, :map, required: true
  attr :currency, :map, required: true
  attr :editing_rate, :string, required: true
  attr :show_all_in_rates, :boolean, required: true
  attr :can_edit, :boolean, default: true

  def rate_cell(assigns) do
    is_editing = assigns.can_edit and assigns.editing_rate == assigns.role.id

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
        class="w-12 text-center text-[10px] font-mono border border-base-content/40 rounded bg-base-100 focus:outline-none focus:border-base-content"
        id={"rate-#{@role.id}"}
        autofocus
      />
    <% else %>
      <%= if @can_edit do %>
        <button
          phx-click="edit_rate"
          phx-value-role-id={@role.id}
          class={"text-[10px] font-mono font-normal normal-case hover:text-base-content/70 cursor-pointer #{if @show_all_in_rates, do: "text-success", else: "text-base-content/40"}"}
        >
          {format_rate(@display_rate, @currency)}
        </button>
      <% else %>
        <span class={"text-[10px] font-mono font-normal normal-case #{if @show_all_in_rates, do: "text-success", else: "text-base-content/40"}"}>
          {format_rate(@display_rate, @currency)}
        </span>
      <% end %>
    <% end %>
    """
  end
end
