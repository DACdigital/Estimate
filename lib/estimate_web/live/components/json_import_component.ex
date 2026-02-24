defmodule EstimateWeb.Components.JsonImportComponent do
  use Phoenix.Component
  import EstimateWeb.CoreComponents

  attr :json_input, :string, required: true
  attr :json_error, :string, default: nil
  attr :json_parsed, :map, default: nil
  attr :validate_event, :string, default: "validate_template_json"
  attr :upload_event, :string, default: "json_file_uploaded"
  attr :download_event, :string, default: "download_json_schema"

  def json_import_panel(assigns) do
    ~H"""
    <div class="space-y-3">
      <div>
        <div class="flex items-center justify-between mb-1.5">
          <label class="block text-xs font-medium text-gray-500">
            Paste JSON
          </label>
          <div class="flex items-center gap-3">
            <button
              type="button"
              phx-click={@download_event}
              class="text-xs text-blue-600 hover:text-blue-700 hover:underline"
            >
              Download example schema
            </button>
            <label class="text-xs text-blue-600 hover:text-blue-700 hover:underline cursor-pointer">
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
          class={"w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm font-mono resize-none #{if @json_error, do: "border-red-300", else: "border-gray-300"}"}
        ><%= @json_input %></textarea>
      </div>

      <p :if={@json_error} class="text-sm text-red-600">{@json_error}</p>

      <div
        :if={@json_parsed && !@json_error}
        class="bg-green-50 border border-green-200 rounded-lg p-3"
      >
        <p class="text-sm text-green-700 font-medium">
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
