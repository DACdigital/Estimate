defmodule EstimateWeb.ProjectLive.Components.NewEstimationModal do
  use EstimateWeb, :html

  import EstimateWeb.Components.JsonImportComponent
  import EstimateWeb.EstimatorLive.Helpers, only: [format_rate: 2]

  attr :show_new_estimation_modal, :boolean, required: true
  attr :estimation_form, :map, required: true
  attr :estimation_source, :string, required: true
  attr :estimations, :list, required: true
  attr :estimation_templates, :list, required: true
  attr :source_estimation_id, :string, default: nil
  attr :selected_estimation_template_id, :string, default: nil
  attr :selected_template_ids, :list, default: []
  attr :role_templates, :list, required: true
  attr :currencies, :list, required: true
  attr :modal_currency_id, :string, default: nil
  attr :modal_currency, :map, default: nil
  attr :org_id, :string, required: true
  attr :json_input, :string, default: nil
  attr :json_error, :string, default: nil
  attr :json_parsed, :map, default: nil

  def new_estimation_modal(assigns) do
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
        <button
          type="button"
          phx-click="set_estimation_source"
          phx-value-source="fresh"
          class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "fresh", do: "border-base-content bg-neutral text-neutral-content", else: "border-base-300 text-base-content/70 hover:border-base-content/20"}"}
        >
          <.icon name="hero-plus" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" /> Start fresh
        </button>
        <button
          type="button"
          phx-click="set_estimation_source"
          phx-value-source="copy"
          disabled={Enum.empty?(@estimations)}
          class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "copy", do: "border-base-content bg-neutral text-neutral-content", else: "border-base-300 text-base-content/70 hover:border-base-content/20"} #{if Enum.empty?(@estimations), do: "opacity-50 cursor-not-allowed"}"}
        >
          <.icon name="hero-document-duplicate" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" />
          Copy existing
        </button>
        <button
          type="button"
          phx-click="set_estimation_source"
          phx-value-source="template"
          disabled={Enum.empty?(@estimation_templates)}
          class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "template", do: "border-base-content bg-neutral text-neutral-content", else: "border-base-300 text-base-content/70 hover:border-base-content/20"} #{if Enum.empty?(@estimation_templates), do: "opacity-50 cursor-not-allowed"}"}
        >
          <.icon name="hero-rectangle-stack" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" />
          From template
        </button>
        <button
          type="button"
          phx-click="set_estimation_source"
          phx-value-source="json"
          class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "json", do: "border-base-content bg-neutral text-neutral-content", else: "border-base-300 text-base-content/70 hover:border-base-content/20"}"}
        >
          <.icon name="hero-arrow-up-tray" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" /> Import JSON
        </button>
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
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">Copy from</label>
            <select
              name="source_estimation_id"
              phx-change="validate_estimation"
              class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
            >
              <%= for est <- @estimations do %>
                <option
                  value={est.id}
                  selected={to_string(est.id) == to_string(@source_estimation_id)}
                >
                  {est.name}
                  <%= if est.is_current do %>
                    (current)
                  <% end %>
                </option>
              <% end %>
            </select>
          </div>

          <div>
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">
              Estimation Name *
            </label>
            <input
              type="text"
              name={@estimation_form[:name].name}
              value={@estimation_form[:name].value}
              placeholder={
                if @estimation_source == "copy", do: "Copy of ...", else: "Q1 2026 Estimate"
              }
              required
              class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
            />
          </div>

          <div>
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">Description</label>
            <textarea
              name={@estimation_form[:description].name}
              rows="2"
              placeholder="Optional description..."
              class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm resize-none"
            ><%= @estimation_form[:description].value %></textarea>
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
                  selected={to_string(currency.id) == to_string(@modal_currency_id)}
                >
                  {currency.code} - {currency.name}
                </option>
              <% end %>
            </select>
          </div>

          <%!-- Roles section for fresh start and JSON import --%>
          <div :if={@estimation_source in ["fresh", "json"]}>
            <label class="block text-xs font-medium text-base-content/60 mb-2">Roles</label>
            <div class="space-y-2 max-h-48 overflow-y-auto border border-base-300 rounded-lg p-3">
              <%= for template <- @role_templates do %>
                <% rate = Enum.find(template.rates, fn r -> r.currency_id == @modal_currency_id end) %>
                <label class="flex items-center justify-between p-2 hover:bg-base-200 rounded cursor-pointer">
                  <div class="flex items-center gap-3">
                    <input
                      type="checkbox"
                      name="template_ids[]"
                      value={template.id}
                      checked={template.id in @selected_template_ids}
                      class="w-4 h-4 text-base-content border-base-content/20 rounded focus:ring-base-content"
                    />
                    <span class="text-sm font-medium text-base-content">{template.name}</span>
                    <span class="text-xs text-base-content/40 font-mono">
                      ({template.abbreviation})
                    </span>
                  </div>
                  <span class="text-sm text-base-content/60">
                    {if rate, do: format_rate(rate.hourly_rate, @modal_currency), else: "-"}
                  </span>
                </label>
              <% end %>
              <%= if Enum.empty?(@role_templates) do %>
                <p class="text-sm text-base-content/60 text-center py-4">
                  No roles defined.
                  <.link navigate={~p"/org/#{@org_id}/roles"} class="text-info hover:underline">
                    Add roles
                  </.link>
                  first.
                </p>
              <% end %>
            </div>
          </div>

          <%!-- Template mode: template selector + roles --%>
          <div :if={@estimation_source == "template"}>
            <label class="block text-xs font-medium text-base-content/60 mb-1.5">
              Estimation Template
            </label>
            <select
              name="estimation_template_id"
              class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
            >
              <%= for tmpl <- @estimation_templates do %>
                <option
                  value={tmpl.id}
                  selected={to_string(tmpl.id) == to_string(@selected_estimation_template_id)}
                >
                  {tmpl.name} ({length(tmpl.epics)} epics, {Enum.sum(
                    Enum.map(tmpl.epics, fn e -> length(e.tasks) end)
                  )} tasks)
                </option>
              <% end %>
            </select>
          </div>

          <div :if={@estimation_source == "template"}>
            <label class="block text-xs font-medium text-base-content/60 mb-2">Roles</label>
            <div class="space-y-2 max-h-48 overflow-y-auto border border-base-300 rounded-lg p-3">
              <%= for template <- @role_templates do %>
                <% rate = Enum.find(template.rates, fn r -> r.currency_id == @modal_currency_id end) %>
                <label class="flex items-center justify-between p-2 hover:bg-base-200 rounded cursor-pointer">
                  <div class="flex items-center gap-3">
                    <input
                      type="checkbox"
                      name="template_ids[]"
                      value={template.id}
                      checked={template.id in @selected_template_ids}
                      class="w-4 h-4 text-base-content border-base-content/20 rounded focus:ring-base-content"
                    />
                    <span class="text-sm font-medium text-base-content">{template.name}</span>
                    <span class="text-xs text-base-content/40 font-mono">
                      ({template.abbreviation})
                    </span>
                  </div>
                  <span class="text-sm text-base-content/60">
                    {if rate, do: format_rate(rate.hourly_rate, @modal_currency), else: "-"}
                  </span>
                </label>
              <% end %>
            </div>
          </div>

          <div :if={@estimation_source == "template"} class="bg-base-200 rounded-lg p-4">
            <div class="flex items-start gap-3">
              <.icon
                name="hero-information-circle"
                class="w-5 h-5 text-base-content/40 flex-shrink-0 mt-0.5"
              />
              <div class="text-sm text-base-content/70">
                <p class="font-medium text-base-content/80">What will be created:</p>
                <ul class="mt-1 space-y-0.5 text-base-content/60">
                  <li>• Epic & task structure from template</li>
                  <li>• Roles from selection above</li>
                  <li>• No hour estimates</li>
                </ul>
              </div>
            </div>
          </div>

          <%!-- Info for copy mode --%>
          <div :if={@estimation_source == "copy"} class="bg-base-200 rounded-lg p-4">
            <div class="flex items-start gap-3">
              <.icon
                name="hero-information-circle"
                class="w-5 h-5 text-base-content/40 flex-shrink-0 mt-0.5"
              />
              <div class="text-sm text-base-content/70">
                <p class="font-medium text-base-content/80">What will be copied:</p>
                <ul class="mt-1 space-y-0.5 text-base-content/60">
                  <li>• All epics and tasks</li>
                  <li>• All hour estimates</li>
                  <li>• Roles and rates</li>
                </ul>
              </div>
            </div>
          </div>
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
end
