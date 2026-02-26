defmodule EstimateWeb.ProjectLive.Components.EstimationDashboard do
  use EstimateWeb, :html

  alias Estimate.EstimationEngine.Calculator

  import EstimateWeb.EstimatorLive.Helpers,
    only: [priority_label: 1, priority_class: 1, format_cost: 2]

  attr :estimation, :map, required: true
  attr :currency, :map, required: true
  attr :dashboard_tab, :atom, required: true
  attr :org_id, :string, required: true
  attr :project, :map, required: true

  def estimation_dashboard(assigns) do
    est = assigns.estimation
    roles = est.roles
    epics = est.epics

    # Calculate totals
    base_hours = Calculator.calc_total_hours(epics)
    base_cost = Calculator.calc_base_cost(epics, roles)

    pm_hours = Calculator.calc_overhead_hours(epics, roles, :pm_overhead)
    pm_cost = Calculator.calc_overhead_cost(epics, roles, :pm_overhead)

    qa_hours = Calculator.calc_overhead_hours(epics, roles, :qa_overhead)
    qa_cost = Calculator.calc_overhead_cost(epics, roles, :qa_overhead)

    risk_hours = Calculator.calc_overhead_hours(epics, roles, :risk_buffer)
    risk_cost = Calculator.calc_overhead_cost(epics, roles, :risk_buffer)

    total_hours =
      base_hours
      |> Decimal.add(pm_hours)
      |> Decimal.add(qa_hours)
      |> Decimal.add(risk_hours)

    total_cost =
      base_cost
      |> Decimal.add(pm_cost)
      |> Decimal.add(qa_cost)
      |> Decimal.add(risk_cost)

    assigns =
      assigns
      |> assign(:base_hours, base_hours)
      |> assign(:base_cost, base_cost)
      |> assign(:pm_hours, pm_hours)
      |> assign(:pm_cost, pm_cost)
      |> assign(:qa_hours, qa_hours)
      |> assign(:qa_cost, qa_cost)
      |> assign(:risk_hours, risk_hours)
      |> assign(:risk_cost, risk_cost)
      |> assign(:total_hours, total_hours)
      |> assign(:total_cost, total_cost)
      |> assign(:roles, roles)
      |> assign(:epics, epics)

    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
      <div class="px-6 py-4 border-b border-base-content/10">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-lg font-semibold text-base-content">Project Summary & Cost Estimates</h2>
            <p class="text-sm text-base-content/60 mt-0.5">
              Hours and costs with overhead calculations ({if @currency, do: @currency.code, else: "-"})
            </p>
          </div>
          <div class="text-right">
            <p class="text-xs text-base-content/40">Based on</p>
            <.link
              navigate={
                ~p"/org/#{@org_id}/projects/#{@project.id}/estimations/#{@estimation.id}/estimator"
              }
              class="text-sm font-medium text-base-content/80 hover:underline"
            >
              {@estimation.name}
            </.link>
          </div>
        </div>
      </div>

      <div class="p-6">
        <%!-- Summary Cards --%>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
          <div class="border border-base-300 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-base-content/60 uppercase tracking-wide mb-1">
              Base
            </p>
            <p class="text-2xl font-bold text-base-content">{format_hours_h(@base_hours)}</p>
            <p class="text-sm text-base-content/60">{format_cost(@base_cost, @currency)}</p>
          </div>

          <div class="border border-base-300 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-base-content/60 uppercase tracking-wide mb-1">
              PM Overhead
            </p>
            <p class="text-2xl font-bold text-base-content">{format_hours_h(@pm_hours)}</p>
            <p class="text-sm text-base-content/60">{format_cost(@pm_cost, @currency)}</p>
          </div>

          <div class="border border-base-300 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-base-content/60 uppercase tracking-wide mb-1">
              QA Overhead
            </p>
            <p class="text-2xl font-bold text-base-content">{format_hours_h(@qa_hours)}</p>
            <p class="text-sm text-base-content/60">{format_cost(@qa_cost, @currency)}</p>
          </div>

          <div class="border border-base-300 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-base-content/60 uppercase tracking-wide mb-1">
              Risk Buffer
            </p>
            <p class="text-2xl font-bold text-base-content">{format_hours_h(@risk_hours)}</p>
            <p class="text-sm text-base-content/60">{format_cost(@risk_cost, @currency)}</p>
          </div>

          <div class="bg-neutral rounded-lg p-4">
            <p class="text-[10px] font-semibold text-neutral-content/60 uppercase tracking-wide mb-1">
              Final Total
            </p>
            <p class="text-2xl font-bold text-neutral-content">{format_hours_h(@total_hours)}</p>
            <p class="text-sm text-neutral-content/60">{format_cost(@total_cost, @currency)}</p>
          </div>
        </div>

        <%!-- Dashboard Tabs --%>
        <div class="mt-6 border-b border-base-300">
          <nav class="flex gap-6">
            <button
              phx-click="set_dashboard_tab"
              phx-value-tab="by_role"
              class={"pb-2 px-1 text-sm font-medium border-b-2 transition-colors #{if @dashboard_tab == :by_role, do: "border-base-content text-base-content", else: "border-transparent text-base-content/60 hover:text-base-content/80"}"}
            >
              By Role
            </button>
            <button
              phx-click="set_dashboard_tab"
              phx-value-tab="by_epic"
              class={"pb-2 px-1 text-sm font-medium border-b-2 transition-colors #{if @dashboard_tab == :by_epic, do: "border-base-content text-base-content", else: "border-transparent text-base-content/60 hover:text-base-content/80"}"}
            >
              By Epic
            </button>
            <button
              phx-click="set_dashboard_tab"
              phx-value-tab="by_priority"
              class={"pb-2 px-1 text-sm font-medium border-b-2 transition-colors #{if @dashboard_tab == :by_priority, do: "border-base-content text-base-content", else: "border-transparent text-base-content/60 hover:text-base-content/80"}"}
            >
              By Priority
            </button>
          </nav>
        </div>

        <%!-- Tab Content --%>
        <div class="mt-4">
          <%= case @dashboard_tab do %>
            <% :by_role -> %>
              <.dashboard_by_role roles={@roles} epics={@epics} currency={@currency} />
            <% :by_epic -> %>
              <.dashboard_by_epic roles={@roles} epics={@epics} currency={@currency} />
            <% :by_priority -> %>
              <.dashboard_by_priority roles={@roles} epics={@epics} currency={@currency} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp dashboard_by_role(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-base-300 text-[11px] font-medium text-base-content/60 uppercase tracking-wider">
            <th class="px-3 py-2 text-left">Role</th>
            <th class="px-3 py-2 text-right">Rate</th>
            <th class="px-3 py-2 text-right">Base</th>
            <th class="px-3 py-2 text-right">PM</th>
            <th class="px-3 py-2 text-right">QA</th>
            <th class="px-3 py-2 text-right">Risk</th>
            <th class="px-3 py-2 text-right">Final</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-base-content/10">
          <%= for role <- @roles, Decimal.compare(Calculator.role_hours(@epics, role.id), 0) == :gt do %>
            <% base_h = Calculator.role_hours(@epics, role.id) %>
            <% base_c = Decimal.mult(base_h, role.hourly_rate) %>
            <% pm_h = Calculator.role_overhead_hours(base_h, role.pm_overhead) %>
            <% pm_c = Calculator.role_overhead_cost(base_c, role.pm_overhead) %>
            <% qa_h = Calculator.role_overhead_hours(base_h, role.qa_overhead) %>
            <% qa_c = Calculator.role_overhead_cost(base_c, role.qa_overhead) %>
            <% risk_h = Calculator.role_overhead_hours(base_h, role.risk_buffer) %>
            <% risk_c = Calculator.role_overhead_cost(base_c, role.risk_buffer) %>
            <% final_h = base_h |> Decimal.add(pm_h) |> Decimal.add(qa_h) |> Decimal.add(risk_h) %>
            <% final_c = base_c |> Decimal.add(pm_c) |> Decimal.add(qa_c) |> Decimal.add(risk_c) %>
            <tr class="hover:bg-base-200">
              <td class="px-3 py-3">
                <span class="font-medium text-base-content">{role.name}</span>
                <span class="text-base-content/40 ml-1">({role.abbreviation})</span>
              </td>
              <td class="px-3 py-3 text-right text-base-content/60">
                {format_cost(role.hourly_rate, @currency)}/h
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-base-content">{format_hours_h(base_h)}</div>
                <div class="text-xs text-base-content/40">{format_cost(base_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-base-content">{format_hours_h(pm_h)}</div>
                <div class="text-xs text-base-content/40">{format_cost(pm_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-base-content">{format_hours_h(qa_h)}</div>
                <div class="text-xs text-base-content/40">{format_cost(qa_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-base-content">{format_hours_h(risk_h)}</div>
                <div class="text-xs text-base-content/40">{format_cost(risk_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="font-semibold text-base-content">{format_hours_h(final_h)}</div>
                <div class="text-xs font-medium text-base-content/70">
                  {format_cost(final_c, @currency)}
                </div>
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr class="border-t-2 border-base-content/20 bg-base-200">
            <td class="px-3 py-3 font-semibold text-base-content" colspan="2">Total</td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-base-content">
                {format_hours_h(Calculator.calc_total_hours(@epics))}
              </div>
              <div class="text-xs text-base-content/60">
                {format_cost(Calculator.calc_base_cost(@epics, @roles), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-base-content">
                {format_hours_h(Calculator.calc_overhead_hours(@epics, @roles, :pm_overhead))}
              </div>
              <div class="text-xs text-base-content/60">
                {format_cost(Calculator.calc_overhead_cost(@epics, @roles, :pm_overhead), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-base-content">
                {format_hours_h(Calculator.calc_overhead_hours(@epics, @roles, :qa_overhead))}
              </div>
              <div class="text-xs text-base-content/60">
                {format_cost(Calculator.calc_overhead_cost(@epics, @roles, :qa_overhead), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-base-content">
                {format_hours_h(Calculator.calc_overhead_hours(@epics, @roles, :risk_buffer))}
              </div>
              <div class="text-xs text-base-content/60">
                {format_cost(Calculator.calc_overhead_cost(@epics, @roles, :risk_buffer), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <% total_h = Calculator.calc_total_with_overhead_hours(@epics, @roles) %>
              <% total_c = Calculator.calc_total_with_overhead_cost(@epics, @roles) %>
              <div class="font-semibold text-base-content">{format_hours_h(total_h)}</div>
              <div class="text-xs font-medium text-base-content/70">
                {format_cost(total_c, @currency)}
              </div>
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp dashboard_by_epic(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-base-300 text-[11px] font-medium text-base-content/60 uppercase tracking-wider">
            <th class="px-3 py-2 text-left">Epic</th>
            <th class="px-3 py-2 text-right">Tasks</th>
            <th class="px-3 py-2 text-right">Base Hours</th>
            <th class="px-3 py-2 text-right">Base Cost</th>
            <th class="px-3 py-2 text-right">With Overhead</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-base-content/10">
          <%= for epic <- @epics do %>
            <% base_h = Calculator.epic_hours(epic) %>
            <% base_c = Calculator.epic_base_cost(epic, @roles) %>
            <% total_c = Calculator.epic_total_with_overhead(epic, @roles) %>
            <tr class="hover:bg-base-200">
              <td class="px-3 py-3 font-medium text-base-content">{epic.name}</td>
              <td class="px-3 py-3 text-right text-base-content/60">{length(epic.tasks)}</td>
              <td class="px-3 py-3 text-right text-base-content">{format_hours_h(base_h)}</td>
              <td class="px-3 py-3 text-right text-base-content/70">
                {format_cost(base_c, @currency)}
              </td>
              <td class="px-3 py-3 text-right font-semibold text-base-content">
                {format_cost(total_c, @currency)}
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr class="border-t-2 border-base-content/20 bg-base-200 font-semibold">
            <td class="px-3 py-3 text-base-content">Total</td>
            <td class="px-3 py-3 text-right text-base-content/70">
              {Enum.reduce(@epics, 0, fn e, acc -> acc + length(e.tasks) end)}
            </td>
            <td class="px-3 py-3 text-right text-base-content">
              {format_hours_h(Calculator.calc_total_hours(@epics))}
            </td>
            <td class="px-3 py-3 text-right text-base-content/70">
              {format_cost(Calculator.calc_base_cost(@epics, @roles), @currency)}
            </td>
            <td class="px-3 py-3 text-right text-base-content">
              {format_cost(Calculator.calc_total_with_overhead_cost(@epics, @roles), @currency)}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp dashboard_by_priority(assigns) do
    priorities = ["must", "should", "could", "wont"]

    priority_data =
      Enum.map(priorities, fn p ->
        tasks =
          Enum.flat_map(assigns.epics, fn epic ->
            Enum.filter(epic.tasks, fn t -> (t.priority || "must") == p end)
          end)

        hours =
          Enum.reduce(tasks, Decimal.new(0), fn task, acc ->
            Enum.reduce(task.estimates, acc, fn est, inner_acc ->
              Decimal.add(inner_acc, est.hours)
            end)
          end)

        cost =
          Enum.reduce(tasks, Decimal.new(0), fn task, acc ->
            Enum.reduce(task.estimates, acc, fn est, inner_acc ->
              role = Enum.find(assigns.roles, &(&1.id == est.estimation_role_id))

              if role do
                base = Decimal.mult(est.hours, role.hourly_rate)
                pm = Decimal.mult(base, Decimal.div(role.pm_overhead, 100))
                qa = Decimal.mult(base, Decimal.div(role.qa_overhead, 100))
                risk = Decimal.mult(base, Decimal.div(role.risk_buffer, 100))

                Decimal.add(
                  inner_acc,
                  base |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk)
                )
              else
                inner_acc
              end
            end)
          end)

        %{priority: p, tasks: length(tasks), hours: hours, cost: cost}
      end)

    assigns = assign(assigns, :priority_data, priority_data)

    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-base-300 text-[11px] font-medium text-base-content/60 uppercase tracking-wider">
            <th class="px-3 py-2 text-left">Priority</th>
            <th class="px-3 py-2 text-right">Tasks</th>
            <th class="px-3 py-2 text-right">Base Hours</th>
            <th class="px-3 py-2 text-right">Total Cost</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-base-content/10">
          <%= for data <- @priority_data do %>
            <tr class="hover:bg-base-200">
              <td class="px-3 py-3">
                <span class={"text-xs px-2 py-1 rounded font-medium #{priority_class(data.priority)}"}>
                  {priority_label(data.priority)}
                </span>
              </td>
              <td class="px-3 py-3 text-right text-base-content/70">{data.tasks}</td>
              <td class="px-3 py-3 text-right text-base-content">{format_hours_h(data.hours)}</td>
              <td class="px-3 py-3 text-right font-semibold text-base-content">
                {format_cost(data.cost, @currency)}
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr class="border-t-2 border-base-content/20 bg-base-200 font-semibold">
            <td class="px-3 py-3 text-base-content">Total</td>
            <td class="px-3 py-3 text-right text-base-content/70">
              {Enum.reduce(@priority_data, 0, fn d, acc -> acc + d.tasks end)}
            </td>
            <td class="px-3 py-3 text-right text-base-content">
              {format_hours_h(
                Enum.reduce(@priority_data, Decimal.new(0), fn d, acc -> Decimal.add(acc, d.hours) end)
              )}
            </td>
            <td class="px-3 py-3 text-right text-base-content">
              {format_cost(
                Enum.reduce(@priority_data, Decimal.new(0), fn d, acc -> Decimal.add(acc, d.cost) end),
                @currency
              )}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp format_hours_h(decimal) do
    if Decimal.compare(decimal, 0) == :eq do
      "0h"
    else
      "#{decimal |> Decimal.round(1) |> Decimal.to_string()}h"
    end
  end
end
