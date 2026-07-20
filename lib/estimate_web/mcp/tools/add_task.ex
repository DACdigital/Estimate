defmodule EstimateWeb.MCP.Tools.AddTask do
  @moduledoc """
  Add a task to an epic (org admin or project owner/editor). Optionally pass
  `efforts` — an object mapping role abbreviations to hours (e.g.
  {"BE": 8, "FE": 4}) — to seed per-role hours in the same call. Omit it to
  create a skeleton and fill hours later in the app or via set_task_effort.
  """

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :epic_id, :string, required: true
    field :name, :string, required: true
    field :description, :string
    field :priority, :enum, values: ["must", "should", "could", "wont"], default: "must"
    field :position, :integer, min: 0

    field :efforts, {:map, :string, {:either, {:float, :integer}}},
      description: ~s(Role abbreviation → hours, e.g. {"BE": 8, "FE": 4})
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:epic, params.epic_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      epic = EstimationEngine.get_epic!(params.epic_id, org_id)
      estimation = EstimationEngine.get_estimation!(epic.estimation_id, org_id)
      roles_by_abbrev = Map.new(estimation.roles, &{&1.abbreviation, &1.id})

      with {:ok, effort_by_role_id} <- resolve_efforts(params[:efforts] || %{}, roles_by_abbrev),
           {:ok, task} <-
             EstimationEngine.create_task_with_estimates(
               params.epic_id,
               task_attrs(params),
               effort_by_role_id
             ) do
        {:ok,
         Serializers.task(task)
         |> Map.put(
           :url,
           Serializers.estimation_url(org_id, estimation.project_id, estimation.id)
         )}
      end
    end)
  end

  defp task_attrs(params) do
    %{
      "name" => params.name,
      "description" => params[:description],
      "priority" => params[:priority] || "must",
      "position" => params[:position] || 0
    }
  end

  defp resolve_efforts(efforts, roles_by_abbrev) do
    Enum.reduce_while(efforts, {:ok, %{}}, fn {abbrev, hours}, {:ok, acc} ->
      case Map.fetch(roles_by_abbrev, abbrev) do
        {:ok, role_id} -> {:cont, {:ok, Map.put(acc, role_id, num(hours))}}
        :error -> {:halt, {:error, unknown_abbrev_msg(abbrev, roles_by_abbrev)}}
      end
    end)
  end

  # `create_task_with_estimates/3` does `to_string(hours)` on whatever value
  # is in this map before casting to the `:decimal` column. `to_string/1` on
  # a float always keeps a `.0` (Elixir never prints a bare integer for a
  # float), and `:decimal` casting preserves that scale verbatim — so a
  # whole-number effort would otherwise serialize back as "8.0" instead of
  # "8". Drop the fraction when the value is integral, same convention as
  # `AddEstimationRole.num/1`.
  defp num(n) when n == trunc(n), do: trunc(n)
  defp num(n), do: n

  defp unknown_abbrev_msg(abbrev, roles_by_abbrev) do
    valid = roles_by_abbrev |> Map.keys() |> Enum.sort() |> Enum.join(", ")
    "unknown role abbreviation \"#{abbrev}\". Valid abbreviations: #{valid}"
  end
end
