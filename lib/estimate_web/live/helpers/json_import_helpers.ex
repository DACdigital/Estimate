defmodule EstimateWeb.JsonImportHelpers do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Estimate.EstimationEngine.JsonImport

  def init_json_assigns(socket) do
    socket
    |> assign(:json_input, "")
    |> assign(:json_error, nil)
    |> assign(:json_parsed, nil)
  end

  def clear_json(socket) do
    init_json_assigns(socket)
  end

  def validate_json(socket, json_string) when json_string in ["", nil] do
    clear_json(socket)
  end

  def validate_json(socket, json_string) do
    case JsonImport.parse_and_validate(json_string) do
      {:ok, parsed} ->
        socket
        |> assign(:json_input, json_string)
        |> assign(:json_parsed, parsed)
        |> assign(:json_error, nil)

      {:error, reason} ->
        socket
        |> assign(:json_input, json_string)
        |> assign(:json_parsed, nil)
        |> assign(:json_error, reason)
    end
  end

  def push_agent_prompt_copy(socket) do
    push_event(socket, "copy_to_clipboard", %{text: JsonImport.agent_prompt()})
  end

  def push_schema_download(socket) do
    schema = JsonImport.example_schema()

    push_event(socket, "download_file", %{
      content: schema,
      filename: "estimation-schema.json",
      content_type: "application/json"
    })
  end
end
