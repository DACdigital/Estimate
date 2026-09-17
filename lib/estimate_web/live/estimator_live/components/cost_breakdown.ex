defmodule EstimateWeb.EstimatorLive.Components.CostBreakdown do
  use EstimateWeb, :html

  import EstimateWeb.EstimatorLive.Helpers

  attr :totals, :map, required: true
  attr :currency, :map, required: true
  attr :show_breakdown, :boolean, required: true

  def cost_breakdown(assigns) do
    ~H"""
    <div class="mt-6 bg-base-100 border border-base-300 rounded-xl overflow-hidden">
      <%!-- Collapsed state --%>
      <div
        :if={!@show_breakdown}
        class="p-4 flex items-center justify-between cursor-pointer hover:bg-base-200 transition-colors"
        phx-click="toggle_breakdown"
      >
        <span class="text-sm text-base-content/60">Total with overheads</span>
        <div class="flex items-center gap-4">
          <span class="text-xl font-bold text-base-content">
            {format_cost(@totals.breakdown.grand_total, @currency)}
          </span>
          <.icon name="hero-chevron-down" class="w-5 h-5 text-base-content/40" />
        </div>
      </div>

      <%!-- Expanded state --%>
      <div :if={@show_breakdown}>
        <div
          class="px-6 py-3 border-b border-base-content/10 bg-base-200 flex items-center justify-between cursor-pointer"
          phx-click="toggle_breakdown"
        >
          <h3 class="text-sm font-semibold text-base-content">Cost Breakdown</h3>
          <.icon name="hero-chevron-up" class="w-5 h-5 text-base-content/40" />
        </div>
        <div class="p-6">
          <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
            <div class="bg-base-200 rounded-lg p-4">
              <p class="text-xs font-medium text-base-content/60 uppercase tracking-wide mb-1">
                Base Cost
              </p>
              <p class="text-xl font-bold text-base-content">
                {format_cost(@totals.breakdown.base_cost, @currency)}
              </p>
              <p class="text-xs text-base-content/40 mt-1">
                {format_hours(@totals.breakdown.total_hours)} hours
              </p>
            </div>
            <div class="bg-info/10 rounded-lg p-4">
              <p class="text-xs font-medium text-info uppercase tracking-wide mb-1">
                PM Overhead
              </p>
              <p class="text-xl font-bold text-info">
                {format_cost(@totals.breakdown.pm, @currency)}
              </p>
              <p class="text-xs text-info/60 mt-1">
                ~{@totals.breakdown.avg_pm}%
              </p>
            </div>
            <div class="bg-secondary/10 rounded-lg p-4">
              <p class="text-xs font-medium text-secondary uppercase tracking-wide mb-1">
                QA Overhead
              </p>
              <p class="text-xl font-bold text-secondary">
                {format_cost(@totals.breakdown.qa, @currency)}
              </p>
              <p class="text-xs text-secondary/60 mt-1">
                ~{@totals.breakdown.avg_qa}%
              </p>
            </div>
            <div class="bg-warning/10 rounded-lg p-4">
              <p class="text-xs font-medium text-warning uppercase tracking-wide mb-1">
                Risk Buffer
              </p>
              <p class="text-xl font-bold text-warning">
                {format_cost(@totals.breakdown.risk, @currency)}
              </p>
              <p class="text-xs text-warning/60 mt-1">
                ~{@totals.breakdown.avg_risk}%
              </p>
            </div>
            <div class="bg-neutral rounded-lg p-4">
              <p class="text-xs font-medium text-neutral-content/60 uppercase tracking-wide mb-1">
                Grand Total
              </p>
              <p class="text-xl font-bold text-neutral-content">
                {format_cost(@totals.breakdown.grand_total, @currency)}
              </p>
              <p class="text-xs text-neutral-content/50 mt-1">incl. overheads</p>
            </div>
          </div>

          <div class="mt-6 overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-base-300">
                  <th class="px-3 py-2 text-left text-xs font-medium text-base-content/60 uppercase">
                    Role
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-base-content/60 uppercase">
                    Hours
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-base-content/60 uppercase">
                    Base
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-info uppercase">
                    PM %
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-secondary uppercase">
                    QA %
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-warning uppercase">
                    Risk %
                  </th>
                  <th class="px-3 py-2 text-right text-xs font-medium text-base-content uppercase">
                    Total
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-content/10">
                <tr :for={r <- @totals.breakdown.roles} class="hover:bg-base-200">
                  <td class="px-3 py-2 text-base-content font-medium">{r.role.name}</td>
                  <td class="px-3 py-2 text-right font-mono text-base-content/70">
                    {format_hours(r.hours)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-base-content/70">
                    {format_cost(r.base, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-info">
                    <span class="text-base-content/40 text-xs">{r.role.pm_overhead}%</span>
                    {format_cost(r.pm, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-secondary">
                    <span class="text-base-content/40 text-xs">{r.role.qa_overhead}%</span>
                    {format_cost(r.qa, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-warning">
                    <span class="text-base-content/40 text-xs">{r.role.risk_buffer}%</span>
                    {format_cost(r.risk, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono font-semibold text-base-content">
                    {format_cost(r.total, @currency)}
                  </td>
                </tr>
              </tbody>
              <tfoot>
                <tr class="border-t-2 border-base-content/20 bg-base-200 font-semibold">
                  <td class="px-3 py-2 text-base-content">Total</td>
                  <td class="px-3 py-2 text-right font-mono text-base-content">
                    {format_hours(@totals.breakdown.total_hours)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-base-content">
                    {format_cost(@totals.breakdown.base_cost, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-info">
                    {format_cost(@totals.breakdown.pm, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-secondary">
                    {format_cost(@totals.breakdown.qa, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-warning">
                    {format_cost(@totals.breakdown.risk, @currency)}
                  </td>
                  <td class="px-3 py-2 text-right font-mono text-base-content">
                    {format_cost(@totals.breakdown.grand_total, @currency)}
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
