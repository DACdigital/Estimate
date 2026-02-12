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
  def parse_and_validate(json_string) when is_binary(json_string) do
    with {:ok, decoded} <- decode_json(json_string),
         :ok <- validate_epics(decoded),
         parsed <- normalize(decoded) do
      {:ok, parsed}
    end
  end

  def parse_and_validate(_), do: {:error, "Input must be a JSON string"}

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
