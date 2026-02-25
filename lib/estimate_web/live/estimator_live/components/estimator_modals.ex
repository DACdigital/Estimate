defmodule EstimateWeb.EstimatorLive.Components.EstimatorModals do
  use EstimateWeb, :html

  import EstimateWeb.EstimatorLive.Helpers

  attr :modal, :atom, required: true
  attr :epic_form, :map, default: nil
  attr :task_form, :map, default: nil
  attr :settings_form, :map, default: nil
  attr :deleting_epic, :map, default: nil
  attr :deleting_task, :map, default: nil
  attr :estimation, :map, required: true
  attr :currencies, :list, default: []
  attr :ai_configured, :boolean, default: false
  attr :ai_loading, :string, default: nil

  def estimator_modals(assigns) do
    ~H"""
    <.epic_modal
      :if={@modal == :epic}
      epic_form={@epic_form}
      ai_configured={@ai_configured}
      ai_loading={@ai_loading}
    />
    <.task_modal
      :if={@modal == :task}
      task_form={@task_form}
      ai_configured={@ai_configured}
      ai_loading={@ai_loading}
    />
    <.delete_epic_modal :if={@deleting_epic} deleting_epic={@deleting_epic} />
    <.delete_task_modal :if={@deleting_task} deleting_task={@deleting_task} />
    <.settings_modal
      :if={@modal == :settings}
      settings_form={@settings_form}
      estimation={@estimation}
      currencies={@currencies}
    />
    <.save_template_modal :if={@modal == :save_template} estimation={@estimation} />
    """
  end

  defp epic_modal(assigns) do
    ~H"""
    <.modal id="epic-modal" show on_cancel={JS.push("close_modal")}>
      <h2 class="text-xl font-semibold text-base-content mb-6">
        {if @epic_form.data.id, do: "Edit Epic", else: "New Epic"}
      </h2>
      <.form for={@epic_form} id="epic-form" phx-submit="save_epic">
        <div class="space-y-4">
          <div>
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">Epic Name *</label>
            <input
              type="text"
              name={@epic_form[:name].name}
              value={@epic_form[:name].value}
              placeholder="e.g. User Authentication"
              required
              class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
            />
          </div>
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <label class="block text-xs font-medium text-base-content/60">Description</label>
              <button
                :if={@ai_configured}
                type="button"
                id="ai-enhance-epic"
                phx-hook="AiEnhance"
                data-textarea-name={@epic_form[:description].name}
                data-name-input={@epic_form[:name].name}
                disabled={@ai_loading != nil}
                class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium bg-purple-50 text-purple-700 border border-purple-200 rounded-md hover:bg-purple-100 hover:border-purple-300 transition-colors disabled:opacity-50"
                title="Enhance with AI"
              >
                <.icon
                  :if={@ai_loading != @epic_form[:description].name}
                  name="hero-sparkles-solid"
                  class="w-3.5 h-3.5"
                />
                <svg
                  :if={@ai_loading == @epic_form[:description].name}
                  class="animate-spin w-3.5 h-3.5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                Enhance with AI
              </button>
            </div>
            <textarea
              name={@epic_form[:description].name}
              rows="5"
              placeholder="Describe the epic scope, goals, and key requirements..."
              class="w-full px-3 py-2.5 bg-base-200 border border-base-content/20 rounded-lg focus:bg-base-100 text-sm resize-y min-h-[80px]"
            ><%= @epic_form[:description].value %></textarea>
          </div>
        </div>
        <div class="mt-6 flex justify-end gap-3">
          <button
            type="button"
            phx-click="close_modal"
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            phx-disable-with="Saving..."
            class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            {if @epic_form.data.id, do: "Save Changes", else: "Create Epic"}
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  defp task_modal(assigns) do
    ~H"""
    <.modal id="task-modal" show on_cancel={JS.push("close_modal")}>
      <h2 class="text-xl font-semibold text-base-content mb-6">
        {if @task_form.data.id, do: "Edit Task", else: "New Task"}
      </h2>
      <.form for={@task_form} id="task-form" phx-submit="save_task" phx-change="validate_task">
        <div class="space-y-4">
          <div>
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">Task Name *</label>
            <input
              type="text"
              name={@task_form[:name].name}
              value={@task_form[:name].value}
              placeholder="e.g. Implement login form"
              required
              class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">Priority (MoSCoW)</label>
            <div class="flex gap-2">
              <%= for p <- ["must", "should", "could", "wont"] do %>
                <label class={"flex-1 text-center py-2 px-3 text-sm rounded-lg border cursor-pointer transition-colors #{if (@task_form[:priority].value || "must") == p, do: "bg-neutral text-neutral-content border-neutral", else: "bg-base-100 text-base-content/70 border-base-content/20 hover:border-base-content/40"}"}>
                  <input
                    type="radio"
                    name={@task_form[:priority].name}
                    value={p}
                    checked={(@task_form[:priority].value || "must") == p}
                    class="sr-only"
                  />
                  {priority_label(p)}
                </label>
              <% end %>
            </div>
          </div>
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <label class="block text-xs font-medium text-base-content/60">Description</label>
              <button
                :if={@ai_configured}
                type="button"
                id="ai-enhance-task"
                phx-hook="AiEnhance"
                data-textarea-name={@task_form[:description].name}
                data-name-input={@task_form[:name].name}
                disabled={@ai_loading != nil}
                class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium bg-purple-50 text-purple-700 border border-purple-200 rounded-md hover:bg-purple-100 hover:border-purple-300 transition-colors disabled:opacity-50"
                title="Enhance with AI"
              >
                <.icon
                  :if={@ai_loading != @task_form[:description].name}
                  name="hero-sparkles-solid"
                  class="w-3.5 h-3.5"
                />
                <svg
                  :if={@ai_loading == @task_form[:description].name}
                  class="animate-spin w-3.5 h-3.5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
                Enhance with AI
              </button>
            </div>
            <textarea
              name={@task_form[:description].name}
              rows="4"
              placeholder="Describe the task scope, acceptance criteria, and technical notes..."
              class="w-full px-3 py-2.5 bg-base-200 border border-base-content/20 rounded-lg focus:bg-base-100 text-sm resize-y min-h-[64px]"
            ><%= @task_form[:description].value %></textarea>
          </div>
        </div>
        <div class="mt-6 flex justify-end gap-3">
          <button
            type="button"
            phx-click="close_modal"
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            phx-disable-with="Saving..."
            class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            {if @task_form.data.id, do: "Save Changes", else: "Create Task"}
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  defp delete_epic_modal(assigns) do
    ~H"""
    <.confirm_modal
      id="delete-epic-modal"
      title="Delete Epic"
      message={"Are you sure you want to delete #{@deleting_epic.name}? This will also delete all its tasks and estimates."}
      confirm_event="delete_epic"
      cancel_event="cancel_delete_epic"
    />
    """
  end

  defp delete_task_modal(assigns) do
    ~H"""
    <.confirm_modal
      id="delete-task-modal"
      title="Delete Task"
      item_name={@deleting_task.name}
      confirm_event="delete_task"
      cancel_event="cancel_delete_task"
    />
    """
  end

  defp settings_modal(assigns) do
    ~H"""
    <.modal id="settings-modal" show on_cancel={JS.push("close_modal")}>
      <h2 class="text-xl font-semibold text-base-content mb-6">Estimation Settings</h2>
      <.form for={@settings_form} id="settings-form" phx-submit="save_settings">
        <div class="space-y-6">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Estimation Name</label>
              <input
                type="text"
                name="name"
                value={@estimation.name}
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Currency</label>
              <select
                name="currency_id"
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              >
                <%= for currency <- @currencies do %>
                  <option
                    value={currency.id}
                    selected={@estimation.currency && currency.id == @estimation.currency.id}
                  >
                    {currency.code} - {currency.name} ({currency.symbol})
                  </option>
                <% end %>
              </select>
            </div>
          </div>

          <div>
            <label class="block text-xs font-medium text-base-content/60 mb-2">Roles & Overheads</label>
            <div class="border border-base-300 rounded-lg overflow-hidden">
              <table class="w-full text-sm">
                <thead>
                  <tr class="bg-base-200 text-[11px] font-medium text-base-content/60 uppercase tracking-wider">
                    <th class="px-3 py-2 text-left">Role</th>
                    <th class="px-3 py-2 text-right w-20">Rate</th>
                    <th class="px-3 py-2 text-right w-16">PM %</th>
                    <th class="px-3 py-2 text-right w-16">QA %</th>
                    <th class="px-3 py-2 text-right w-16">Risk %</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-content/10">
                  <%= for role <- @estimation.roles do %>
                    <tr class="hover:bg-base-200">
                      <td class="px-3 py-2">
                        <div class="flex items-center gap-2">
                          <span class="w-6 h-6 rounded bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-semibold text-[10px]">
                            {role.abbreviation}
                          </span>
                          <span class="text-base-content">{role.name}</span>
                        </div>
                      </td>
                      <td class="px-3 py-2">
                        <input
                          type="number"
                          step="1"
                          min="0"
                          name={"roles[#{role.id}][hourly_rate]"}
                          value={format_percent(role.hourly_rate)}
                          class="w-full px-2 py-1 border border-base-300 rounded text-sm font-mono text-right hover:border-base-content/30"
                        />
                      </td>
                      <td class="px-3 py-2">
                        <input
                          type="number"
                          step="1"
                          min="0"
                          max="100"
                          name={"roles[#{role.id}][pm_overhead]"}
                          value={format_percent(role.pm_overhead)}
                          class="w-full px-2 py-1 border border-base-300 rounded text-sm font-mono text-right hover:border-base-content/30"
                        />
                      </td>
                      <td class="px-3 py-2">
                        <input
                          type="number"
                          step="1"
                          min="0"
                          max="100"
                          name={"roles[#{role.id}][qa_overhead]"}
                          value={format_percent(role.qa_overhead)}
                          class="w-full px-2 py-1 border border-base-300 rounded text-sm font-mono text-right hover:border-base-content/30"
                        />
                      </td>
                      <td class="px-3 py-2">
                        <input
                          type="number"
                          step="1"
                          min="0"
                          max="100"
                          name={"roles[#{role.id}][risk_buffer]"}
                          value={format_percent(role.risk_buffer)}
                          class="w-full px-2 py-1 border border-base-300 rounded text-sm font-mono text-right hover:border-base-content/30"
                        />
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <div class="mt-3 flex items-center gap-2">
              <input
                type="text"
                name="new_role_name"
                placeholder="Role name"
                phx-keydown="add_estimation_role"
                phx-key="Enter"
                class="flex-1 px-2 py-1.5 border border-base-300 rounded text-sm hover:border-base-content/30"
              />
              <input
                type="text"
                name="new_role_abbr"
                placeholder="ABBR"
                maxlength="5"
                phx-keydown="add_estimation_role"
                phx-key="Enter"
                class="w-16 px-2 py-1.5 border border-base-300 rounded text-sm font-mono uppercase text-center hover:border-base-content/30"
              />
              <button
                type="button"
                phx-click="add_estimation_role"
                class="px-3 py-1.5 bg-neutral text-neutral-content text-sm rounded hover:bg-neutral/90 transition-colors"
              >
                Add
              </button>
            </div>

            <p class="text-xs text-base-content/40 mt-1.5">Changes apply only to this estimation</p>
          </div>
        </div>
        <div class="mt-6 flex justify-end gap-3">
          <button
            type="button"
            phx-click="close_modal"
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            phx-disable-with="Saving..."
            class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            Save
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  defp save_template_modal(assigns) do
    ~H"""
    <.modal id="save-template-modal" show on_cancel={JS.push("close_modal")}>
      <h2 class="text-xl font-semibold text-base-content mb-4">Save as Template</h2>
      <p class="text-sm text-base-content/60 mb-4">
        Save the epic & task structure as a reusable template. No hours or roles will be included.
      </p>
      <form phx-submit="save_as_template">
        <div>
          <label class="block text-xs font-medium text-base-content/60 mb-1.5">Template Name *</label>
          <input
            type="text"
            name="template_name"
            value={@estimation.name}
            required
            autofocus
            class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
          />
        </div>
        <div class="mt-6 flex justify-end gap-3">
          <button
            type="button"
            phx-click="close_modal"
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            phx-disable-with="Saving..."
            class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            Save Template
          </button>
        </div>
      </form>
    </.modal>
    """
  end
end
