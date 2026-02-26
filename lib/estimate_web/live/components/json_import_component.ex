defmodule EstimateWeb.Components.JsonImportComponent do
  use Phoenix.Component
  import EstimateWeb.CoreComponents

  attr :json_input, :string, required: true
  attr :json_error, :string, default: nil
  attr :json_parsed, :map, default: nil
  attr :validate_event, :string, default: "validate_template_json"
  attr :upload_event, :string, default: "json_file_uploaded"
  attr :download_event, :string, default: "download_json_schema"
  attr :copy_prompt_event, :string, default: "copy_agent_prompt"

  def json_import_panel(assigns) do
    ~H"""
    <div class="space-y-3">
      <div>
        <div class="flex items-center justify-between mb-1.5">
          <label class="block text-xs font-medium text-base-content/60">
            Paste JSON
          </label>
          <div class="flex items-center gap-3">
            <button
              type="button"
              phx-click={@download_event}
              class="text-xs text-info hover:text-info/80 hover:underline"
            >
              Download example schema
            </button>
            <div class="flex items-center gap-1">
              <button
                type="button"
                phx-click={@copy_prompt_event}
                class="text-xs text-info hover:text-info/80 hover:underline inline-flex items-center gap-1"
              >
                <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Copy agent prompt
              </button>
              <div class="relative group">
                <.icon
                  name="hero-question-mark-circle"
                  class="w-3.5 h-3.5 text-base-content/40 cursor-help"
                />
                <div class="hidden group-hover:block absolute right-0 bottom-full mb-1 w-56 px-2.5 py-1.5 text-xs text-base-content bg-base-200 border border-base-300 rounded-lg shadow-lg z-50">
                  Copy a prompt for ChatGPT, Claude or Gemini that will extract tasks from your meeting notes, chat logs, or any text into the JSON format above
                </div>
              </div>
            </div>
            <label class="text-xs text-info hover:text-info/80 hover:underline cursor-pointer">
              Or upload file
              <input
                type="file"
                accept=".json"
                class="hidden"
                id="json-file-input"
                phx-hook="JsonFileReader"
              />
            </label>
          </div>
        </div>
        <textarea
          name="json_input"
          rows="12"
          phx-debounce="500"
          placeholder={"{\n  \"epics\": [\n    {\n      \"name\": \"Epic name\",\n      \"tasks\": [\n        { \"name\": \"Task name\", \"priority\": \"must\" }\n      ]\n    }\n  ]\n}"}
          class={"w-full px-3 py-2 border rounded-lg text-sm font-mono resize-none #{if @json_error, do: "border-error/50", else: "border-base-content/20"}"}
        ><%= @json_input %></textarea>
      </div>

      <p :if={@json_error} class="text-sm text-error">{@json_error}</p>

      <div
        :if={@json_parsed && !@json_error}
        class="bg-success/10 border border-success/20 rounded-lg p-3"
      >
        <p class="text-sm text-success font-medium">
          <.icon name="hero-check-circle" class="w-4 h-4 inline-block -mt-0.5 mr-1" />
          {length(@json_parsed.epics)} epics, {Enum.sum(
            Enum.map(@json_parsed.epics, fn e -> length(e.tasks) end)
          )} tasks will be imported
        </p>
      </div>
    </div>
    """
  end
end
