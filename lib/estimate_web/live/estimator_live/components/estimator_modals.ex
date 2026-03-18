defmodule EstimateWeb.EstimatorLive.Components.EstimatorModals do
  use EstimateWeb, :html
  use EstimateWeb.FormClasses

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
            <label class={@label_class}>Epic Name *</label>
            <input
              type="text"
              name={@epic_form[:name].name}
              value={@epic_form[:name].value}
              placeholder="e.g. User Authentication"
              required
              class={@input_class}
            />
          </div>
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <label class="block text-xs font-medium text-base-content/60">Description</label>
              <.ai_enhance_button
                :if={@ai_configured}
                id="ai-enhance-epic"
                textarea_name={@epic_form[:description].name}
                name_input={@epic_form[:name].name}
                ai_loading={@ai_loading}
              />
            </div>
            <textarea
              name={@epic_form[:description].name}
              rows="5"
              placeholder="Describe the epic scope, goals, and key requirements..."
              class="w-full px-3 py-2.5 bg-base-200 border border-base-content/20 rounded-lg focus:bg-base-100 text-sm resize-y min-h-[80px]"
            ><%= @epic_form[:description].value %></textarea>
          </div>
        </div>
        <.modal_footer submit_label={if @epic_form.data.id, do: "Save Changes", else: "Create Epic"} />
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
            <label class={@label_class}>Task Name *</label>
            <input
              type="text"
              name={@task_form[:name].name}
              value={@task_form[:name].value}
              placeholder="e.g. Implement login form"
              required
              class={@input_class}
            />
          </div>
          <div>
            <label class={@label_class}>Priority (MoSCoW)</label>
            <div class="flex gap-2">
              <label
                :for={p <- ["must", "should", "could", "wont"]}
                class={"flex-1 text-center py-2 px-3 text-sm rounded-lg border cursor-pointer transition-colors #{if (@task_form[:priority].value || "must") == p, do: "bg-neutral text-neutral-content border-neutral", else: "bg-base-100 text-base-content/70 border-base-content/20 hover:border-base-content/40"}"}
              >
                <input
                  type="radio"
                  name={@task_form[:priority].name}
                  value={p}
                  checked={(@task_form[:priority].value || "must") == p}
                  class="sr-only"
                />
                {priority_label(p)}
              </label>
            </div>
          </div>
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <label class="block text-xs font-medium text-base-content/60">Description</label>
              <.ai_enhance_button
                :if={@ai_configured}
                id="ai-enhance-task"
                textarea_name={@task_form[:description].name}
                name_input={@task_form[:name].name}
                ai_loading={@ai_loading}
              />
            </div>
            <textarea
              name={@task_form[:description].name}
              rows="4"
              placeholder="Describe the task scope, acceptance criteria, and technical notes..."
              class="w-full px-3 py-2.5 bg-base-200 border border-base-content/20 rounded-lg focus:bg-base-100 text-sm resize-y min-h-[64px]"
            ><%= @task_form[:description].value %></textarea>
          </div>
        </div>
        <.modal_footer submit_label={if @task_form.data.id, do: "Save Changes", else: "Create Task"} />
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
    assigns = assign(assigns, :label_class, @label_class)
    assigns = assign(assigns, :input_class, @input_class)

    ~H"""
    <.modal id="settings-modal" show on_cancel={JS.push("close_modal")}>
      <h2 class="text-xl font-semibold text-base-content mb-6">Estimation Settings</h2>
      <.form for={@settings_form} id="settings-form" phx-submit="save_settings">
        <div class="space-y-6">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class={@label_class}>Estimation Name</label>
              <input type="text" name="name" value={@estimation.name} class={@input_class} />
            </div>
            <div>
              <label class={@label_class}>Currency</label>
              <select name="currency_id" class={@input_class}>
                <option
                  :for={currency <- @currencies}
                  value={currency.id}
                  selected={@estimation.currency && currency.id == @estimation.currency.id}
                >
                  {currency.code} - {currency.name} ({currency.symbol})
                </option>
              </select>
            </div>
          </div>

          <div>
            <label class="block text-xs font-medium text-base-content/60 mb-2">
              Roles & Overheads
            </label>
            <div class="border border-base-300 rounded-lg overflow-hidden">
              <table class="w-full text-sm">
                <thead>
                  <tr class="bg-base-200 text-[11px] font-medium text-base-content/60 uppercase tracking-wider">
                    <th class="px-3 py-2 text-left">Role</th>
                    <th class="px-3 py-2 text-right w-20">Rate</th>
                    <th class="px-3 py-2 text-right w-16">PM %</th>
                    <th class="px-3 py-2 text-right w-16">QA %</th>
                    <th class="px-3 py-2 text-right w-16">Risk %</th>
                    <th class="w-8"></th>
                  </tr>
                </thead>
                <tbody
                  id="roles-sortable"
                  phx-hook="TemplateSortable"
                  data-sort-event="reorder_roles"
                  class="divide-y divide-base-content/10"
                >
                  <tr :for={role <- @estimation.roles} data-id={role.id} class="hover:bg-base-200">
                    <td class="px-3 py-2">
                      <div class="flex items-center gap-2">
                        <span class="drag-handle cursor-grab text-base-content/30 hover:text-base-content/60">
                          <.icon name="hero-bars-3-mini" class="w-4 h-4" />
                        </span>
                        <input
                          type="text"
                          name={"roles[#{role.id}][abbreviation]"}
                          value={role.abbreviation}
                          maxlength="5"
                          class="w-12 px-1 py-1 border border-base-300 rounded text-[10px] font-semibold text-center uppercase bg-gradient-to-br from-indigo-500 to-purple-600 text-white hover:border-base-content/30"
                        />
                        <input
                          type="text"
                          name={"roles[#{role.id}][name]"}
                          value={role.name}
                          class="w-full px-2 py-1 border border-base-300 rounded text-sm hover:border-base-content/30"
                        />
                      </div>
                    </td>
                    <.role_number_input field="hourly_rate" role={role} />
                    <.role_number_input field="pm_overhead" role={role} max="100" />
                    <.role_number_input field="qa_overhead" role={role} max="100" />
                    <.role_number_input field="risk_buffer" role={role} max="100" />
                    <td class="px-1 py-2">
                      <button
                        type="button"
                        phx-click="delete_estimation_role"
                        phx-value-id={role.id}
                        data-confirm="Delete role and all its estimates?"
                        class="text-base-content/40 hover:text-error transition-colors"
                      >
                        <.icon name="hero-trash-mini" class="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
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
        <.modal_footer submit_label="Save" />
      </.form>
    </.modal>
    """
  end

  defp save_template_modal(assigns) do
    assigns = assign(assigns, :label_class, @label_class)
    assigns = assign(assigns, :input_class, @input_class)

    ~H"""
    <.modal id="save-template-modal" show on_cancel={JS.push("close_modal")}>
      <h2 class="text-xl font-semibold text-base-content mb-4">Save as Template</h2>
      <p class="text-sm text-base-content/60 mb-4">
        Save the epic & task structure as a reusable template. No hours or roles will be included.
      </p>
      <.form for={%{}} as={:template} id="template-form" phx-submit="save_as_template">
        <div>
          <label class={@label_class}>Template Name *</label>
          <input
            type="text"
            name="template_name"
            value={@estimation.name}
            required
            autofocus
            class={@input_class}
          />
        </div>
        <.modal_footer submit_label="Save Template" />
      </.form>
    </.modal>
    """
  end

  # Shared components

  attr :id, :string, required: true
  attr :textarea_name, :string, required: true
  attr :name_input, :string, required: true
  attr :ai_loading, :string, default: nil

  defp ai_enhance_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-hook="AiEnhance"
      data-textarea-name={@textarea_name}
      data-name-input={@name_input}
      disabled={@ai_loading != nil}
      class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium bg-purple-50 text-purple-700 border border-purple-200 rounded-md hover:bg-purple-100 hover:border-purple-300 transition-colors disabled:opacity-50"
      title="Enhance with AI"
    >
      <.icon
        :if={@ai_loading != @textarea_name}
        name="hero-sparkles-solid"
        class="w-3.5 h-3.5"
      />
      <svg
        :if={@ai_loading == @textarea_name}
        class="animate-spin w-3.5 h-3.5"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
      >
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path
          class="opacity-75"
          fill="currentColor"
          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
        />
      </svg>
      Enhance with AI
    </button>
    """
  end

  attr :submit_label, :string, required: true

  defp modal_footer(assigns) do
    ~H"""
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
        {@submit_label}
      </button>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :role, :map, required: true
  attr :max, :string, default: nil

  defp role_number_input(assigns) do
    assigns = assign(assigns, :value, format_number(Map.get(assigns.role, String.to_existing_atom(assigns.field))))

    ~H"""
    <td class="px-3 py-2">
      <input
        type="number"
        step="1"
        min="0"
        max={@max}
        name={"roles[#{@role.id}][#{@field}]"}
        value={@value}
        class="w-full px-2 py-1 border border-base-300 rounded text-sm font-mono text-right hover:border-base-content/30"
      />
    </td>
    """
  end

  defp format_number(nil), do: ""

  defp format_number(%Decimal{} = d) do
    if Decimal.equal?(d, Decimal.round(d, 0)),
      do: Decimal.to_integer(d) |> to_string(),
      else: Decimal.to_string(d)
  end

  defp format_number(val), do: to_string(val)
end
