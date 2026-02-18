defmodule EstimateWeb.EstimatorLive.Components.CostBreakdown do
  use EstimateWeb, :html

  alias Estimate.EstimationEngine.Calculator
  import EstimateWeb.EstimatorLive.Helpers

  attr :epics, :list, required: true
  attr :roles, :list, required: true
  attr :currency, :map, required: true
  attr :show_breakdown, :boolean, required: true

  def cost_breakdown(assigns) do
    ~H"""
    <div class="mt-6 bg-white border border-gray-200 rounded-xl overflow-hidden">
      <%!-- Collapsed state --%>
      <div
        :if={!@show_breakdown}
        class="p-4 flex items-center justify-between cursor-pointer hover:bg-gray-50 transition-colors"
        phx-click="toggle_breakdown"
      >
        <span class="text-sm text-gray-500">Total with overheads</span>
        <div class="flex items-center gap-4">
          <span class="text-xl font-bold text-gray-900">
            {format_cost(Calculator.grand_total_with_overhead(@epics, @roles), @currency)}
          </span>
          <.icon name="hero-chevron-down" class="w-5 h-5 text-gray-400" />
        </div>
      </div>

      <%!-- Expanded state --%>
      <div :if={@show_breakdown}>
        <div
          class="px-6 py-3 border-b border-gray-100 bg-gray-50 flex items-center justify-between cursor-pointer"
          phx-click="toggle_breakdown"
        >
          <h3 class="text-sm font-semibold text-gray-900">Cost Breakdown</h3>
          <.icon name="hero-chevron-up" class="w-5 h-5 text-gray-400" />
        </div>
        <div class="p-6">
          <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
            <div class="bg-gray-50 rounded-lg p-4">
              <p class="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">Base Cost</p>
              <p class="text-xl font-bold text-gray-900">
                {format_cost(Calculator.total_base_cost(@epics, @roles), @currency)}
              </p>
              <p class="text-xs text-gray-400 mt-1">
                {format_hours(Calculator.calc_total_hours(@epics))} hours
              </p>
            </div>
            <div class="bg-blue-50 rounded-lg p-4">
              <p class="text-xs font-medium text-blue-600 uppercase tracking-wide mb-1">
                PM Overhead
              </p>
              <p class="text-xl font-bold text-blue-900">
                {format_cost(Calculator.total_pm_overhead(@epics, @roles), @currency)}
              </p>
              <p class="text-xs text-blue-400 mt-1">
                ~{Calculator.weighted_avg_overhead(@epics, @roles, &Calculator.role_pm_overhead/2)}%
              </p>
            </div>
            <div class="bg-purple-50 rounded-lg p-4">
              <p class="text-xs font-medium text-purple-600 uppercase tracking-wide mb-1">
                QA Overhead
              </p>
              <p class="text-xl font-bold text-purple-900">
                {format_cost(Calculator.total_qa_overhead(@epics, @roles), @currency)}
              </p>
              <p class="text-xs text-purple-400 mt-1">
                ~{Calculator.weighted_avg_overhead(@epics, @roles, &Calculator.role_qa_overhead/2)}%
              </p>
            </div>
            <div class="bg-amber-50 rounded-lg p-4">
              <p class="text-xs font-medium text-amber-600 uppercase tracking-wide mb-1">
                Risk Buffer
              </p>
              <p class="text-xl font-bold text-amber-900">
                {format_cost(Calculator.total_risk_buffer(@epics, @roles), @currency)}
              </p>
              <p class="text-xs text-amber-400 mt-1">
                ~{Calculator.weighted_avg_overhead(@epics, @roles, &Calculator.role_risk_buffer/2)}%
              </p>
            </div>
            <div class="bg-gray-900 rounded-lg p-4">
              <p class="text-xs font-medium text-gray-400 uppercase tracking-wide mb-1">
                Grand Total
              </p>
              <p class="text-xl font-bold text-white">
                {format_cost(Calculator.grand_total_with_overhead(@epics, @roles), @currency)}
              </p>
              <p class="text-xs text-gray-500 mt-1">incl. overheads</p>
            </div>
          </div>

          <div class="mt-6 overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-gray-200">
                  <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                    Role
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                    Hours
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                    Base
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-blue-500 uppercase">
                    PM %
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-purple-500 uppercase">
                    QA %
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-amber-500 uppercase">
                    Risk %
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-gray-900 uppercase">
                    Total
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100">
                <%= for role <- @roles, Decimal.compare(Calculator.role_hours(@epics, role.id), 0) == :gt do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-3 py-2 text-gray-900 font-medium">{role.name}</td>
                    <td class="px-3 py-2 text-right font-mono text-gray-600">
                      {format_hours(Calculator.role_hours(@epics, role.id))}
                    </td>
                    <td class="px-3 py-2 text-right font-mono text-gray-600">
                      {format_cost(Calculator.role_base_cost(@epics, role), @currency)}
                    </td>
                    <td class="px-3 py-2 text-right font-mono text-blue-600">
                      <span class="text-gray-400 text-xs">{role.pm_overhead}%</span>
                      {format_cost(Calculator.role_pm_overhead(@epics, role), @currency)}
                    </td>
                    <td class="px-3 py-2 text-right font-mono text-purple-600">
                      <span class="text-gray-400 text-xs">{role.qa_overhead}%</span>
                      {format_cost(Calculator.role_qa_overhead(@epics, role), @currency)}
                    </td>
                    <td class="px-3 py-2 text-right font-mono text-amber-600">
                      <span class="text-gray-400 text-xs">{role.risk_buffer}%</span>
                      {format_cost(Calculator.role_risk_buffer(@epics, role), @currency)}
                    </td>
                    <td class="px-3 py-2 text-right font-mono font-semibold text-gray-900">
                      {format_cost(
                        Calculator.role_base_cost(@epics, role)
                        |> Decimal.add(Calculator.role_pm_overhead(@epics, role))
                        |> Decimal.add(Calculator.role_qa_overhead(@epics, role))
                        |> Decimal.add(Calculator.role_risk_buffer(@epics, role)),
                        @currency
                      )}
                    </td>
                  </tr>
                <% end %>
              </tbody>
              <tfoot>
                <tr class="border-t-2 border-gray-300 bg-gray-50 font-semibold">
                  <td class="px-3 py-2 text-gray-900">Total</td>
                  <td class="px-3 py-2 text-right font-mono text-gray-900">
                    {format_hours(Calculator.calc_total_hours(@epics))}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-gray-900">
                    {format_cost(Calculator.total_base_cost(@epics, @roles), @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-blue-700">
                    {format_cost(Calculator.total_pm_overhead(@epics, @roles), @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-purple-700">
                    {format_cost(Calculator.total_qa_overhead(@epics, @roles), @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-amber-700">
                    {format_cost(Calculator.total_risk_buffer(@epics, @roles), @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-gray-900">
                    {format_cost(Calculator.grand_total_with_overhead(@epics, @roles), @currency)}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
