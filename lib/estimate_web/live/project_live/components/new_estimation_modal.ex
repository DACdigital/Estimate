defmodule EstimateWeb.ProjectLive.Components.NewEstimationModal do
  use EstimateWeb, :html
  use EstimateWeb.FormClasses

  import EstimateWeb.Components.JsonImportComponent

  attr :show_new_estimation_modal, :boolean, required: true
  attr :estimation_form, :map, required: true
  attr :estimation_source, :string, required: true
  attr :estimations, :list, required: true
  attr :estimation_templates, :list, required: true
  attr :source_estimation_id, :string, default: nil
  attr :selected_estimation_template_id, :string, default: nil
  attr :modal_roles, :list, default: []
  attr :currencies, :list, required: true
  attr :modal_currency_id, :string, default: nil
  attr :modal_currency, :map, default: nil
  attr :org_id, :string, required: true
  attr :json_input, :string, default: nil
  attr :json_error, :string, default: nil
  attr :json_parsed, :map, default: nil

  def new_estimation_modal(assigns) do
    assigns = assign(assigns, :label_class, @label_class)
    assigns = assign(assigns, :input_class, @input_class)

    ~H"""
    <.modal
      :if={@show_new_estimation_modal}
      id="new-estimation-modal"
      show
      on_cancel={JS.push("close_estimation_modal")}
    >
      <h2 class="text-xl font-semibold text-base-content mb-4">New Estimation</h2>

      <%!-- Source Selection --%>
      <div class="flex gap-2 mb-6">
        <.source_tab_button
          source="fresh"
          label="Start fresh"
          icon="hero-plus"
          current={@estimation_source}
        />
        <.source_tab_button
          source="copy"
          label="Copy existing"
          icon="hero-document-duplicate"
          current={@estimation_source}
          disabled={Enum.empty?(@estimations)}
        />
        <.source_tab_button
          source="template"
          label="From template"
          icon="hero-rectangle-stack"
          current={@estimation_source}
          disabled={Enum.empty?(@estimation_templates)}
        />
        <.source_tab_button
          source="json"
          label="Import JSON"
          icon="hero-arrow-up-tray"
          current={@estimation_source}
        />
      </div>

      <.form
        for={@estimation_form}
        id="new-estimation-form"
        phx-submit="create_estimation"
        phx-change="validate_estimation"
      >
        <input type="hidden" name="source" value={@estimation_source} />

        <div class="space-y-5">
          <%!-- JSON Import --%>
          <div :if={@estimation_source == "json"}>
            <.json_import_panel
              json_input={@json_input}
              json_error={@json_error}
              json_parsed={@json_parsed}
            />
          </div>

          <%!-- Copy source selector --%>
          <div :if={@estimation_source == "copy"}>
            <label class={@label_class}>Copy from</label>
            <select
              name="source_estimation_id"
              phx-change="validate_estimation"
              class={@input_class}
            >
              <option
                :for={est <- @estimations}
                value={est.id}
                selected={to_string(est.id) == to_string(@source_estimation_id)}
              >
                {est.name}{if est.is_current, do: " (current)"}
              </option>
            </select>
          </div>

          <div>
            <label class={@label_class}>Estimation Name *</label>
            <input
              type="text"
              name={@estimation_form[:name].name}
              value={@estimation_form[:name].value}
              placeholder={
                if @estimation_source == "copy", do: "Copy of ...", else: "Q1 2026 Estimate"
              }
              required
              class={@input_class}
            />
          </div>

          <div>
            <label class={@label_class}>Description</label>
            <textarea
              name={@estimation_form[:description].name}
              rows="2"
              placeholder="Optional description..."
              class={@input_class <> " resize-none"}
            ><%= @estimation_form[:description].value %></textarea>
          </div>

          <div>
            <label class={@label_class}>Currency</label>
            <select name="currency_id" class={@input_class}>
              <option
                :for={currency <- @currencies}
                value={currency.id}
                selected={to_string(currency.id) == to_string(@modal_currency_id)}
              >
                {currency.code} - {currency.name}
              </option>
            </select>
          </div>

          <%!-- Template mode: template selector --%>
          <div :if={@estimation_source == "template"}>
            <label class={@label_class}>Estimation Template</label>
            <select name="estimation_template_id" class={@input_class}>
              <option
                :for={tmpl <- @estimation_templates}
                value={tmpl.id}
                selected={to_string(tmpl.id) == to_string(@selected_estimation_template_id)}
              >
                {tmpl.name} ({length(tmpl.epics)} epics, {Enum.sum(
                  Enum.map(tmpl.epics, fn e -> length(e.tasks) end)
                )} tasks)
              </option>
            </select>
          </div>

          <%!-- Editable roles for fresh, template, json --%>
          <div :if={@estimation_source in ["fresh", "template", "json"]}>
            <label class="block text-xs font-medium text-base-content/60 mb-2">Roles</label>
            <div class="border border-base-300 rounded-lg overflow-hidden">
              <div
                :if={@modal_roles != []}
                id="modal-roles-sortable"
                phx-hook="TemplateSortable"
                data-sort-event="reorder_modal_roles"
                class="divide-y divide-base-content/10"
              >
                <div
                  :for={role <- @modal_roles}
                  data-id={role.temp_id}
                  class="flex items-center gap-2 px-3 py-2 hover:bg-base-200"
                >
                  <span class="drag-handle cursor-grab text-base-content/30 hover:text-base-content/60">
                    <.icon name="hero-bars-3-mini" class="w-4 h-4" />
                  </span>
                  <input
                    type="text"
                    name={"roles[#{role.temp_id}][abbreviation]"}
                    value={role.abbreviation}
                    placeholder="ABR"
                    maxlength="5"
                    class="w-12 px-1 py-1 border border-base-300 rounded text-[10px] font-semibold text-center uppercase bg-gradient-to-br from-indigo-500 to-purple-600 text-white hover:border-base-content/30"
                  />
                  <input
                    type="text"
                    name={"roles[#{role.temp_id}][name]"}
                    value={role.name}
                    placeholder="Role name"
                    class="flex-1 px-2 py-1 border border-base-300 rounded text-sm"
                  />
                  <input
                    type="text"
                    name={"roles[#{role.temp_id}][hourly_rate]"}
                    value={role.hourly_rate}
                    placeholder="0"
                    inputmode="decimal"
                    class="w-20 px-2 py-1 border border-base-300 rounded text-sm text-right"
                  />
                  <span class="text-xs text-base-content/40 whitespace-nowrap">
                    {if @modal_currency, do: "#{@modal_currency.symbol}/h", else: "/h"}
                  </span>
                  <button
                    type="button"
                    phx-click="remove_modal_role"
                    phx-value-temp-id={role.temp_id}
                    class="text-base-content/40 hover:text-error transition-colors"
                  >
                    <.icon name="hero-x-mark-mini" class="w-4 h-4" />
                  </button>
                </div>
              </div>
              <div :if={@modal_roles == []} class="px-3 py-6 text-center text-sm text-base-content/50">
                No roles. Add at least one role below.
              </div>
            </div>
            <div class="flex items-center justify-between mt-2">
              <button
                type="button"
                phx-click="add_modal_role"
                class="text-sm text-base-content/60 hover:text-base-content transition-colors inline-flex items-center gap-1"
              >
                <.icon name="hero-plus-mini" class="w-4 h-4" /> Add role
              </button>
              <button
                type="button"
                phx-click="reset_modal_roles"
                class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors"
              >
                Reset to defaults
              </button>
            </div>
          </div>

          <.info_panel :if={@estimation_source == "template"} title="What will be created:">
            <li>Epic & task structure from template</li>
            <li>Roles from list above</li>
            <li>No hour estimates</li>
          </.info_panel>

          <.info_panel :if={@estimation_source == "copy"} title="What will be copied:">
            <li>All epics and tasks</li>
            <li>All hour estimates</li>
            <li>Roles and rates</li>
          </.info_panel>
        </div>

        <div class="mt-6 flex justify-end gap-3">
          <button
            type="button"
            phx-click="close_estimation_modal"
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={@estimation_source == "json" && !@json_parsed}
            phx-disable-with={if @estimation_source == "copy", do: "Copying...", else: "Creating..."}
            class={"px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium #{if @estimation_source == "json" && !@json_parsed, do: "opacity-50 cursor-not-allowed"}"}
          >
            {if @estimation_source == "copy", do: "Create Copy", else: "Create"}
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  # Shared components

  attr :source, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :current, :string, required: true
  attr :disabled, :boolean, default: false

  defp source_tab_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_estimation_source"
      phx-value-source={@source}
      disabled={@disabled}
      class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors inline-flex items-center justify-center whitespace-nowrap gap-1.5 #{if @current == @source, do: "border-base-content bg-neutral text-neutral-content", else: "border-base-300 text-base-content/70 hover:border-base-content/20"} #{if @disabled, do: "opacity-50 cursor-not-allowed"}"}
    >
      <.icon name={@icon} class="w-4 h-4 shrink-0" /> {@label}
    </button>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp info_panel(assigns) do
    ~H"""
    <div class="bg-base-200 rounded-lg p-4">
      <div class="flex items-start gap-3">
        <.icon
          name="hero-information-circle"
          class="w-5 h-5 text-base-content/40 flex-shrink-0 mt-0.5"
        />
        <div class="text-sm text-base-content/70">
          <p class="font-medium text-base-content/80">{@title}</p>
          <ul class="mt-1 space-y-0.5 text-base-content/60">
            {render_slot(@inner_block)}
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
