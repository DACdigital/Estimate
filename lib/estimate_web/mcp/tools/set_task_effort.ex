defmodule EstimateWeb.MCP.Tools.SetTaskEffort do
  @moduledoc "Set (or overwrite) the hours a role spends on a task (org admin or project owner/editor). `role` is a role abbreviation or an estimation-role UUID."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :task_id, :string, required: true

    field :role, :string,
      required: true,
      description: "Role abbreviation (e.g. BE) or estimation-role UUID"

    field :hours, {:either, {:float, :integer}}, required: true, description: "Hours (>= 0)"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:task, params.task_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      task = EstimationEngine.get_task!(params.task_id, org_id)
      epic = EstimationEngine.get_epic!(task.epic_id, org_id)
      estimation = EstimationEngine.get_estimation!(epic.estimation_id, org_id)

      with {:ok, role} <- find_role(estimation.roles, params.role),
           {:ok, te} <-
             EstimationEngine.upsert_task_estimate(
               task.id,
               role.id,
               %{hours: to_string(num(params.hours))},
               estimation.id
             ) do
        {:ok,
         %{
           task_id: task.id,
           role_id: role.id,
           abbreviation: role.abbreviation,
           hours: Serializers.decimal(te.hours),
           url: Serializers.estimation_url(org_id, estimation.project_id, estimation.id)
         }}
      end
    end)
  end

  defp find_role(roles, ref) do
    case Enum.find(roles, &(&1.abbreviation == ref or &1.id == ref)) do
      nil ->
        valid = roles |> Enum.map(& &1.abbreviation) |> Enum.sort() |> Enum.join(", ")
        {:error, ~s(unknown role "#{ref}". Valid abbreviations: #{valid})}

      role ->
        {:ok, role}
    end
  end

  # `to_string/1` on a float always keeps a `.0` (Elixir never prints a bare
  # integer for a float), and the `:decimal` column cast preserves that scale
  # verbatim — so a whole-number `hours` would otherwise serialize back as
  # "5.0" instead of "5". Drop the fraction when the value is integral, same
  # convention as `AddTask.num/1` and `UpdateEstimationRole.num/1`.
  defp num(n) when n == trunc(n), do: trunc(n)
  defp num(n), do: n
end
