defmodule Estimate.Portfolio do
  @moduledoc """
  The Portfolio context for managing projects and collaborators.
  """

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.Portfolio.{Project, ProjectCollaborator, ProjectRole}
  alias Estimate.Accounts
  alias Estimate.CRM
  alias Estimate.Search

  def list_projects(org_id) do
    Repo.ensure_org_context(fn ->
      from(p in Project,
        join: c in assoc(p, :customer),
        where: c.organization_id == ^org_id,
        preload: [:customer, :currency],
        order_by: [desc: p.updated_at]
      )
      |> Repo.all()
    end)
  end

  @doc """
  Role-aware project listing. Admins/owners see all projects,
  regular members see only projects they collaborate on.
  """
  def list_projects(org_id, _user_id, role) when role in ["owner", "admin"] do
    list_projects(org_id)
  end

  def list_projects(org_id, user_id, _role) do
    list_user_projects(user_id, org_id)
  end

  def list_user_projects(user_id, org_id) do
    Repo.ensure_org_context(fn ->
      from(p in Project,
        join: pc in ProjectCollaborator,
        on: pc.project_id == p.id,
        join: c in assoc(p, :customer),
        where: pc.user_id == ^user_id and c.organization_id == ^org_id,
        preload: [:customer, :currency],
        order_by: [desc: p.updated_at]
      )
      |> Repo.all()
    end)
  end

  @doc """
  Role-aware project listing scoped to a customer.
  Admins/owners see all, members see only collaborated projects.
  """
  def list_customer_projects(customer_id, org_id, _user_id, role)
      when role in ["owner", "admin"] do
    Repo.ensure_org_context(fn ->
      from(p in Project,
        where: p.customer_id == ^customer_id and p.organization_id == ^org_id,
        order_by: [desc: p.updated_at]
      )
      |> Repo.all()
    end)
  end

  def list_customer_projects(customer_id, org_id, user_id, _role) do
    Repo.ensure_org_context(fn ->
      from(p in Project,
        join: pc in ProjectCollaborator,
        on: pc.project_id == p.id,
        where:
          p.customer_id == ^customer_id and
            p.organization_id == ^org_id and
            pc.user_id == ^user_id,
        order_by: [desc: p.updated_at]
      )
      |> Repo.all()
    end)
  end

  def get_project!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(p in Project,
        where: p.id == ^id and p.organization_id == ^org_id,
        preload: [:customer, :currency, :collaborators]
      )
      |> Repo.one!()
    end)
  end

  def get_project_with_roles!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(p in Project,
        where: p.id == ^id and p.organization_id == ^org_id,
        preload: [:customer, :currency, :roles]
      )
      |> Repo.one!()
    end)
  end

  def reload_project_with_roles(%Project{} = project) do
    Repo.ensure_org_context(fn ->
      Repo.preload(project, [:customer, :currency, :roles], force: true)
    end)
  end

  def get_project_for_user!(id, user_id) do
    Repo.ensure_org_context(fn ->
      from(p in Project,
        join: pc in ProjectCollaborator,
        on: pc.project_id == p.id,
        where: p.id == ^id and pc.user_id == ^user_id,
        preload: [:customer, :currency, collaborators: :user]
      )
      |> Repo.one!()
    end)
  end

  @doc """
  Creates a project and adds the creator as owner collaborator in a transaction.
  If currency_id is not provided, inherits from customer's default_currency.
  Also copies role templates from organization with rates for project's currency.
  """
  def create_project(attrs, customer_id, user_id, org_id) do
    Repo.ensure_org_context(fn ->
      attrs = maybe_inherit_currency(attrs, customer_id, org_id)
      customer = CRM.get_customer!(customer_id, org_id)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:project, fn _ ->
        Project.changeset(%Project{}, Map.put(attrs, "customer_id", customer_id))
      end)
      |> Ecto.Multi.insert(:collaborator, fn %{project: project} ->
        ProjectCollaborator.changeset(%ProjectCollaborator{}, %{
          project_id: project.id,
          user_id: user_id,
          role: "owner"
        })
      end)
      |> Ecto.Multi.run(:roles, fn _repo, %{project: project} ->
        case copy_roles_from_templates(project, customer.organization_id) do
          :ok -> {:ok, :copied}
          {:error, changeset} -> {:error, changeset}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{project: project}} ->
          project = Repo.preload(project, [:customer, :currency, :roles])
          Search.index_project(project)
          {:ok, project}

        {:error, :project, changeset, _} ->
          {:error, changeset}

        {:error, :collaborator, changeset, _} ->
          {:error, changeset}
      end
    end)
  end

  defp maybe_inherit_currency(attrs, customer_id, org_id) do
    currency_id = attrs["currency_id"] || attrs[:currency_id]

    if is_nil(currency_id) or currency_id == "" do
      case CRM.get_customer!(customer_id, org_id) do
        %{default_currency_id: cid} when not is_nil(cid) ->
          Map.put(attrs, "currency_id", cid)

        _ ->
          attrs
      end
    else
      attrs
    end
  end

  def update_project(%Project{} = project, attrs) do
    Repo.ensure_org_context(fn ->
      project
      |> Project.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, project} ->
          project = Repo.preload(project, [:customer, :currency], force: true)
          Search.index_project(project)
          {:ok, project}

        error ->
          error
      end
    end)
  end

  def delete_project(%Project{} = project) do
    Repo.ensure_org_context(fn ->
      result = Repo.delete(project)

      case result do
        {:ok, project} ->
          Search.remove_index("project", project.id)
          {:ok, project}

        error ->
          error
      end
    end)
  end

  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  ## Collaborators

  def add_collaborator(project_id, user_id, role \\ "viewer") do
    Repo.ensure_org_context(fn ->
      %ProjectCollaborator{}
      |> ProjectCollaborator.changeset(%{project_id: project_id, user_id: user_id, role: role})
      |> Repo.insert()
    end)
  end

  def update_collaborator_role(%ProjectCollaborator{} = collab, role) do
    Repo.ensure_org_context(fn ->
      collab
      |> ProjectCollaborator.changeset(%{role: role})
      |> Repo.update()
    end)
  end

  def remove_collaborator(%ProjectCollaborator{} = collab) do
    Repo.ensure_org_context(fn ->
      Repo.delete(collab)
    end)
  end

  def get_collaborator(project_id, user_id) do
    Repo.ensure_org_context(fn ->
      Repo.get_by(ProjectCollaborator, project_id: project_id, user_id: user_id)
    end)
  end

  def list_collaborators(project_id) do
    Repo.ensure_org_context(fn ->
      from(pc in ProjectCollaborator,
        where: pc.project_id == ^project_id,
        preload: [:user]
      )
      |> Repo.all()
    end)
  end

  def list_available_members(project_id, org_id) do
    Repo.ensure_org_context(fn ->
      existing_ids =
        from(pc in ProjectCollaborator, where: pc.project_id == ^project_id, select: pc.user_id)
        |> Repo.all()

      from(m in Estimate.Accounts.Membership,
        where: m.organization_id == ^org_id and m.user_id not in ^existing_ids,
        join: u in assoc(m, :user),
        preload: [:user],
        order_by: u.name
      )
      |> Repo.all()
    end)
  end

  ## Project Roles

  def list_project_roles(project_id) do
    Repo.ensure_org_context(fn ->
      from(pr in ProjectRole,
        where: pr.project_id == ^project_id,
        order_by: [asc: pr.position, asc: pr.name]
      )
      |> Repo.all()
    end)
  end

  def get_project_role!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(pr in ProjectRole,
        join: p in assoc(pr, :project),
        where: pr.id == ^id and p.organization_id == ^org_id
      )
      |> Repo.one!()
    end)
  end

  def list_project_roles_by_ids(role_ids) when is_list(role_ids) do
    Repo.ensure_org_context(fn ->
      from(pr in ProjectRole,
        where: pr.id in ^role_ids,
        order_by: [asc: pr.position, asc: pr.name]
      )
      |> Repo.all()
    end)
  end

  def create_project_role(project_id, attrs) do
    Repo.ensure_org_context(fn ->
      %ProjectRole{}
      |> ProjectRole.changeset(Map.put(attrs, "project_id", project_id))
      |> Repo.insert()
    end)
  end

  @doc """
  Updates a ProjectRole and syncs changes to all linked EstimationRoles.
  """
  def update_project_role(%ProjectRole{} = role, attrs) do
    Repo.ensure_org_context(fn ->
      Ecto.Multi.new()
      |> Ecto.Multi.update(:project_role, ProjectRole.changeset(role, attrs))
      |> Ecto.Multi.run(:sync_estimation_roles, fn _repo, %{project_role: updated_role} ->
        # Update all EstimationRoles that link to this ProjectRole
        from(er in Estimate.EstimationEngine.EstimationRole,
          where: er.project_role_id == ^updated_role.id
        )
        |> Repo.update_all(
          set: [
            name: updated_role.name,
            abbreviation: updated_role.abbreviation,
            hourly_rate: updated_role.hourly_rate,
            pm_overhead: updated_role.pm_overhead,
            qa_overhead: updated_role.qa_overhead,
            risk_buffer: updated_role.risk_buffer
          ]
        )

        {:ok, :synced}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{project_role: role}} -> {:ok, role}
        {:error, :project_role, changeset, _} -> {:error, changeset}
      end
    end)
  end

  def delete_project_role(%ProjectRole{} = role) do
    Repo.ensure_org_context(fn ->
      Repo.delete(role)
    end)
  end

  def change_project_role(%ProjectRole{} = role, attrs \\ %{}) do
    ProjectRole.changeset(role, attrs)
  end

  @doc """
  Copies role templates from org to project, using rates for project's currency.
  Also copies PM overhead, QA overhead, and risk buffer percentages.
  """
  def copy_roles_from_templates(%Project{} = project, org_id) do
    Repo.ensure_org_context(fn ->
      templates = Accounts.list_role_templates(org_id)
      currency_id = project.currency_id

      Enum.reduce_while(templates, :ok, fn template, :ok ->
        rate = Enum.find(template.rates, fn r -> r.currency_id == currency_id end)
        hourly_rate = if rate, do: rate.hourly_rate, else: Decimal.new(0)

        %ProjectRole{}
        |> ProjectRole.changeset(%{
          name: template.name,
          abbreviation: template.abbreviation,
          position: template.position,
          hourly_rate: hourly_rate,
          pm_overhead: template.pm_overhead || Decimal.new(0),
          qa_overhead: template.qa_overhead || Decimal.new(0),
          risk_buffer: template.risk_buffer || Decimal.new(0),
          project_id: project.id
        })
        |> Repo.insert()
        |> case do
          {:ok, _} -> {:cont, :ok}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
    end)
  end
end
