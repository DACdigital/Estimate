defmodule EstimateWeb.MCP.Tools.GetProject do
  @moduledoc "Fetch one project with its roles and estimation summaries."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Project UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn claims -> load_project(claims, id) end) do
      {:ok, {project, roles, estimations}} ->
        body =
          project
          |> Serializers.project()
          |> Map.put(:detailed_description, project.detailed_description)
          |> Map.put(:roles, Enum.map(roles, &Serializers.project_role/1))
          |> Map.put(:estimations, Enum.map(estimations, &Serializers.estimation_summary/1))

        {:reply, Response.json(Response.tool(), body), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "project not found"), frame}
    end
  end

  # Mirrors the LiveView authz split: admins load by org, members only
  # via their collaborator join (raises NoResultsError otherwise, which
  # Scope.fetch maps to not_found — no existence oracle).
  # Admins reuse preloaded roles (sorted to match list_project_roles/1 order);
  # members fetch roles separately since get_project_for_user! doesn't preload.
  defp load_project(%{org_id: org_id, user_id: user_id, role: role}, id) do
    {project, roles} =
      if role in ["owner", "admin"] do
        project = Estimate.Portfolio.get_project_with_roles!(id, org_id)
        {project, project.roles |> Enum.sort_by(&{&1.position, &1.name})}
      else
        project = Estimate.Portfolio.get_project_for_user!(id, user_id)
        {project, Estimate.Portfolio.list_project_roles(project.id)}
      end

    estimations = Estimate.EstimationEngine.list_estimations(project.id, org_id)
    {project, roles, estimations}
  end
end
