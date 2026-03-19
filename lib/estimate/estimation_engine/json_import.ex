defmodule Estimate.EstimationEngine.JsonImport do
  @moduledoc """
  Parses and validates JSON for estimation import.
  """

  @valid_priorities ~w(must should could wont)
  @max_name_length 255
  @max_description_length 10_000

  @doc """
  Parses a JSON string and validates the estimation structure.
  Returns {:ok, parsed} or {:error, reason}.
  """
  @max_json_size 1_000_000

  def parse_and_validate(json_string) when is_binary(json_string) do
    with :ok <- check_size(json_string),
         {:ok, decoded} <- decode_json(json_string),
         :ok <- validate_epics(decoded),
         parsed <- normalize(decoded) do
      {:ok, parsed}
    end
  end

  def parse_and_validate(_), do: {:error, "Input must be a JSON string"}

  defp check_size(str) when byte_size(str) > @max_json_size,
    do: {:error, "JSON too large (max #{@max_json_size} bytes)"}

  defp check_size(_str), do: :ok

  defp decode_json(str) do
    case Jason.decode(str) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _} -> {:error, "JSON must be an object"}
      {:error, %Jason.DecodeError{} = e} -> {:error, "Invalid JSON: #{Exception.message(e)}"}
    end
  end

  defp validate_epics(%{"epics" => epics}) when is_list(epics) and length(epics) > 0 do
    epics
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {epic, idx}, :ok ->
      case validate_epic(epic, idx) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_epics(%{"epics" => []}), do: {:error, "Must have at least 1 epic"}
  defp validate_epics(%{"epics" => _}), do: {:error, "\"epics\" must be an array"}
  defp validate_epics(_), do: {:error, "Missing required field \"epics\""}

  defp validate_epic(%{"name" => name, "tasks" => tasks} = epic, idx)
       when is_binary(name) and is_list(tasks) and length(tasks) > 0 do
    description = Map.get(epic, "description", "")

    cond do
      String.length(name) > @max_name_length ->
        {:error, "Epic ##{idx} name exceeds #{@max_name_length} characters"}

      is_binary(description) and String.length(description) > @max_description_length ->
        {:error, "Epic ##{idx} description exceeds #{@max_description_length} characters"}

      true ->
        tasks
        |> Enum.with_index(1)
        |> Enum.reduce_while(:ok, fn {task, tidx}, :ok ->
          case validate_task(task, idx, tidx) do
            :ok -> {:cont, :ok}
            {:error, _} = err -> {:halt, err}
          end
        end)
    end
  end

  defp validate_epic(%{"name" => _, "tasks" => []}, idx),
    do: {:error, "Epic ##{idx} must have at least 1 task"}

  defp validate_epic(%{"name" => _, "tasks" => _}, idx),
    do: {:error, "Epic ##{idx}: \"tasks\" must be an array"}

  defp validate_epic(%{"name" => _}, idx),
    do: {:error, "Epic ##{idx} missing \"tasks\""}

  defp validate_epic(_, idx),
    do: {:error, "Epic ##{idx} missing \"name\""}

  defp validate_task(%{"name" => name} = task, epic_idx, task_idx) when is_binary(name) do
    priority = Map.get(task, "priority")
    description = Map.get(task, "description", "")

    cond do
      String.length(name) > @max_name_length ->
        {:error,
         "Epic ##{epic_idx}, task ##{task_idx} name exceeds #{@max_name_length} characters"}

      is_binary(description) and String.length(description) > @max_description_length ->
        {:error,
         "Epic ##{epic_idx}, task ##{task_idx} description exceeds #{@max_description_length} characters"}

      priority && priority not in @valid_priorities ->
        {:error,
         "Invalid priority \"#{priority}\". Must be one of: #{Enum.join(@valid_priorities, ", ")}"}

      true ->
        :ok
    end
  end

  defp validate_task(_, epic_idx, task_idx),
    do: {:error, "Epic ##{epic_idx}, task ##{task_idx} missing \"name\""}

  defp normalize(decoded) do
    %{
      estimation: Map.get(decoded, "estimation"),
      description: Map.get(decoded, "description"),
      currency: Map.get(decoded, "currency"),
      epics:
        Enum.map(decoded["epics"], fn epic ->
          %{
            name: epic["name"],
            description: Map.get(epic, "description"),
            tasks:
              Enum.map(epic["tasks"], fn task ->
                %{
                  name: task["name"],
                  description: Map.get(task, "description"),
                  priority: Map.get(task, "priority", "must")
                }
              end)
          }
        end)
    }
  end

  @doc """
  Returns an LLM prompt that extracts tasks from unstructured text into estimation JSON.
  """
  def agent_prompt do
    schema =
      %{
        "estimation" => "Estimation Name",
        "description" => "Optional description for the estimation",
        "currency" => "EUR",
        "epics" => [
          %{
            "name" => "Epic Name",
            "description" => "Optional epic description",
            "tasks" => [
              %{
                "name" => "Task Name",
                "description" => "Optional task description",
                "priority" => "must"
              }
            ]
          }
        ]
      }
      |> Jason.encode!(pretty: true)

    """
    # Task Extraction Agent Prompt

    ## Role

    You are a project estimation assistant. Your job is to analyze unstructured text and extract actionable tasks, group them into logical epics, and output a structured JSON estimation.

    ## Input

    You will receive:

    1. **A reference JSON schema** (below) that defines the expected output format.
    2. **Unstructured text** — this could be meeting transcripts (e.g. Fireflies export), Slack/Discord chat logs, email threads, handwritten notes, or any freeform project discussion.

    ### Reference Schema

    ```json
    #{schema}
    ```

    **Field rules:**

    - `estimation`: Derive a meaningful name from the project or meeting context. If unclear, use a sensible default.
    - `description`: A brief summary of what the estimation covers, derived from context.
    - `currency`: Include only if a currency is explicitly mentioned in the text. Omit the field otherwise.
    - `epics[].name`: A concise label for a logical grouping of related tasks (e.g. "Frontend Development", "Infrastructure", "Design").
    - `epics[].description`: Optional — include only when the text provides enough context to summarize the epic's scope.
    - `tasks[].name`: A clear, concise action item. Avoid vague language — prefer specifics (e.g. "Implement JWT authentication" over "Do auth stuff").
    - `tasks[].description`: Optional — include when the text contains additional detail, acceptance criteria, or technical notes about the task.
    - `tasks[].priority`: Assign using the MoSCoW method based on context clues in the text:
      - **must** — Explicitly stated as critical, blocking, required, MVP, or non-negotiable.
      - **should** — Important but not blocking; described as "we really need" or "high priority" without being a hard requirement.
      - **could** — Nice-to-have, mentioned as future improvement, stretch goal, or "if we have time".
      - **wont** — Explicitly deferred, rejected, out of scope, or agreed to skip for now.
      - When priority is ambiguous, default to **should**.

    ## Instructions

    1. **Read the entire input text** before extracting anything.
    2. **Identify distinct tasks** — look for action items, feature requests, bug mentions, technical decisions, and deliverables.
    3. **Group tasks into epics** by theme or domain (e.g. frontend, backend, design, infrastructure, testing, documentation). Do not create an epic with only one task unless it is clearly a standalone concern.
    4. **Deduplicate** — if the same task is mentioned multiple times (common in meetings), consolidate into a single entry and merge any extra context into the description.
    5. **Ignore noise** — skip greetings, small talk, off-topic tangents, and anything that is not an actionable work item or project decision.
    6. **Preserve technical specifics** — if the text mentions specific technologies, endpoints, libraries, or constraints, include them in the task description.
    7. **Output only valid JSON** — no markdown fences, no commentary, no preamble. Just the raw JSON object.

    ## Output

    Return a single JSON object matching the reference schema. Nothing else.

    ---

    ## Text to analyze

    ```
    [PASTE YOUR TEXT HERE]
    ```
    """
  end

  @doc """
  Returns the example JSON schema string for download.
  """
  def example_schema do
    %{
      "estimation" => "My Estimation Name (optional)",
      "description" => "Optional description for the estimation",
      "currency" => "EUR (optional — currency code, e.g. EUR, USD, CHF)",
      "epics" => [
        %{
          "name" => "Frontend Development",
          "description" => "Optional epic description",
          "tasks" => [
            %{
              "name" => "Login Page",
              "description" => "Optional task description",
              "priority" => "must (optional — must/should/could/wont, defaults to must)"
            },
            %{
              "name" => "Dashboard",
              "priority" => "should"
            }
          ]
        },
        %{
          "name" => "Backend API",
          "tasks" => [
            %{
              "name" => "Authentication Endpoint",
              "description" => "JWT-based auth",
              "priority" => "must"
            },
            %{
              "name" => "User Management CRUD",
              "priority" => "could"
            }
          ]
        }
      ]
    }
    |> Jason.encode!(pretty: true)
  end
end
