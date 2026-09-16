defmodule Estimate.Portfolio.ProjectCollaborator do
  use Estimate.Schema
  import Ecto.Changeset

  @roles ~w(owner editor viewer)
  @edit_roles ~w(owner editor)

  schema "project_collaborators" do
    field :role, :string, default: "viewer"

    belongs_to :project, Estimate.Portfolio.Project
    belongs_to :user, Estimate.Accounts.User

    timestamps()
  end

  def changeset(collaborator, attrs) do
    collaborator
    |> cast(attrs, [:role, :project_id, :user_id])
    |> validate_required([:role, :project_id, :user_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:project_id, :user_id])
  end

  def roles, do: @roles
  def edit_roles, do: @edit_roles
end
