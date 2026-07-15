defmodule EstimateWeb.ProjectLive.Components.OverviewTab do
  use EstimateWeb, :html

  import EstimateWeb.ProjectLive.Components.EstimationDashboard

  attr :project, :map, required: true
  attr :form, :map, required: true
  attr :current_estimation, :map, default: nil
  attr :dashboard_tab, :atom, required: true
  attr :org_id, :string, required: true
  attr :can_edit_project, :boolean, required: true
  attr :can_delete_project, :boolean, required: true
  attr :currencies, :list, required: true
  attr :customer_key, :string, default: nil

  def overview_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Estimation Dashboard --%>
      <%= if @current_estimation do %>
        <.estimation_dashboard
          estimation={@current_estimation}
          currency={@current_estimation.currency}
          dashboard_tab={@dashboard_tab}
          org_id={@org_id}
          project={@project}
        />
      <% else %>
        <div class="bg-base-100 border border-base-300 rounded-xl p-8 text-center">
          <.icon name="hero-calculator" class="w-12 h-12 text-base-content/30 mx-auto" />
          <p class="mt-3 text-base-content/60">No estimations yet</p>
          <.link
            :if={@can_edit_project}
            navigate={~p"/org/#{@org_id}/projects/#{@project.id}/estimations/new"}
            class="mt-4 inline-block px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            Create Estimation
          </.link>
        </div>
      <% end %>

      <%!-- Project Details Card --%>
      <.form for={@form} id="project-form" phx-submit="save" phx-change="validate">
        <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
          <div class="p-6 space-y-4">
            <h2 class="text-lg font-semibold text-base-content">Project Details</h2>

            <%!-- Top row: Name, Key, Status --%>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="md:col-span-1">
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  Project Name *
                </label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  placeholder="Website Redesign"
                  required
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  Project Key
                </label>
                <div class="flex items-center gap-1">
                  <span class="px-3 py-2 bg-base-200 border border-base-content/20 rounded-l-lg text-sm text-base-content/60 font-mono">
                    {@customer_key || "---"}
                  </span>
                  <span class="text-base-content/40">-</span>
                  <input
                    type="text"
                    name={@form[:key].name}
                    value={@form[:key].value}
                    placeholder="PROJ"
                    maxlength="10"
                    class="w-full px-3 py-2 border border-base-content/20 rounded-r-lg text-sm font-mono uppercase"
                  />
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">Status</label>
                <select
                  name={@form[:status].name}
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
                >
                  <option value="active" selected={@form[:status].value == "active"}>Active</option>
                  <option value="completed" selected={@form[:status].value == "completed"}>
                    Completed
                  </option>
                  <option value="archived" selected={@form[:status].value == "archived"}>
                    Archived
                  </option>
                </select>
              </div>
            </div>

            <%!-- Default Currency --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Default Currency
              </label>
              <select
                name={@form[:currency_id].name}
                class="w-full max-w-md px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              >
                <option value="">None</option>
                <%= for currency <- @currencies do %>
                  <option
                    value={currency.id}
                    selected={to_string(currency.id) == to_string(@form[:currency_id].value)}
                  >
                    {currency.code} - {currency.name}
                  </option>
                <% end %>
              </select>
              <p class="text-xs text-base-content/40 mt-1">Used as default for new estimations</p>
            </div>

            <%!-- Short Description --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Short Description
              </label>
              <input
                type="text"
                name={@form[:short_description].name}
                value={@form[:short_description].value}
                placeholder="One-liner about the project"
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>

            <%!-- Detailed Description --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Detailed Description
              </label>
              <textarea
                name={@form[:detailed_description].name}
                rows="4"
                placeholder="Comprehensive scope and details..."
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm resize-none"
              ><%= @form[:detailed_description].value %></textarea>
            </div>

            <%!-- Repository URL --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Repository URL
              </label>
              <input
                type="url"
                name={@form[:repository_url].name}
                value={@form[:repository_url].value}
                placeholder="https://github.com/org/repo"
                class="w-full max-w-md px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>

            <%!-- Customer (readonly) --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Customer</label>
              <%= if @project.customer do %>
                <.link
                  navigate={~p"/org/#{@org_id}/customers/#{@project.customer.id}"}
                  class="inline-flex items-center gap-1 text-sm text-info hover:text-info"
                >
                  {@project.customer.name}
                  <.icon name="hero-arrow-top-right-on-square" class="w-3.5 h-3.5" />
                </.link>
              <% else %>
                <span class="text-sm text-base-content/40">Not set</span>
              <% end %>
            </div>
          </div>

          <div
            :if={@can_edit_project}
            class="px-6 py-3 bg-base-200 border-t border-base-300 flex justify-end"
          >
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
            >
              Save
            </button>
          </div>
        </div>
      </.form>

      <%!-- Danger Zone --%>
      <div
        :if={@can_delete_project}
        class="bg-base-100 border border-error/30 rounded-xl overflow-hidden"
      >
        <div class="p-6">
          <h2 class="text-lg font-semibold text-error">Danger Zone</h2>
          <p class="text-sm text-base-content/60 mt-1">
            Permanently delete this project and all its data.
          </p>
          <button
            phx-click="confirm_delete_project"
            class="mt-4 px-4 py-2 border border-error/30 text-error text-sm rounded-lg hover:bg-error/10 transition-colors font-medium"
          >
            Delete Project
          </button>
        </div>
      </div>
    </div>
    """
  end
end
