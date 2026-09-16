defmodule EstimateWeb.MCP.Authz do
  @moduledoc """
  Write-side authorization for MCP tools. RLS scopes rows to the org only,
  so these gates add the app's role + project-collaborator rules, mirroring
  the web app. All functions run inside `Scope.with_scope/2` (RLS context set).
  """

  alias Estimate.{Organizations, Portfolio, EstimationEngine}
  alias Estimate.MCP.OAuth.Scopes
  alias Estimate.Accounts.Membership
  alias Estimate.Portfolio.ProjectCollaborator

  def require_write_enabled(%{org_id: org_id}) do
    if Organizations.mcp_write_enabled?(org_id), do: :ok, else: {:error, :write_disabled}
  end

  def require_write_scope(%{scopes: scopes}) do
    if Scopes.write?(scopes), do: :ok, else: {:error, :insufficient_scope}
  end

  def require_org_admin(%{role: role}) do
    if role in Membership.admin_roles(), do: :ok, else: {:error, :unauthorized}
  end

  def require_org_admin(_), do: {:error, :unauthorized}

  def require_can_edit_project(project_id, %{role: role, user_id: user_id}) do
    cond do
      role in Membership.admin_roles() -> :ok
      collaborator_role(project_id, user_id) in ProjectCollaborator.edit_roles() -> :ok
      true -> {:error, :unauthorized}
    end
  end

  def ensure_project(project_id, org_id) do
    Portfolio.get_project!(project_id, org_id)
    {:ok, project_id}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def project_id_for(kind, id, org_id) do
    case do_resolve(kind, id, org_id) do
      nil -> {:error, :not_found}
      project_id -> {:ok, project_id}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp do_resolve(:estimation, id, org_id),
    do: EstimationEngine.get_estimation_project_id(id, org_id)

  defp do_resolve(:epic, id, org_id),
    do:
      EstimationEngine.get_estimation_project_id(
        EstimationEngine.get_epic!(id, org_id).estimation_id,
        org_id
      )

  defp do_resolve(:role, id, org_id),
    do:
      EstimationEngine.get_estimation_project_id(
        EstimationEngine.get_role!(id, org_id).estimation_id,
        org_id
      )

  defp do_resolve(:task, id, org_id) do
    epic_id = EstimationEngine.get_task!(id, org_id).epic_id

    EstimationEngine.get_estimation_project_id(
      EstimationEngine.get_epic!(epic_id, org_id).estimation_id,
      org_id
    )
  end

  defp collaborator_role(project_id, user_id) do
    case Portfolio.get_collaborator(project_id, user_id) do
      %{role: role} -> role
      _ -> nil
    end
  end
end
