defmodule Estimate.EstimationEngine.Estimation do
  use Estimate.Schema
  import Ecto.Changeset

  schema "estimations" do
    field :name, :string
    field :description, :string
    field :is_current, :boolean, default: false
    field :deleted_at, :utc_datetime

    belongs_to :project, Estimate.Portfolio.Project
    belongs_to :currency, Estimate.Accounts.Currency
    belongs_to :organization, Estimate.Accounts.Organization
    has_many :roles, Estimate.EstimationEngine.EstimationRole
    has_many :epics, Estimate.EstimationEngine.Epic

    timestamps()
  end

  def changeset(estimation, attrs) do
    estimation
    |> cast(attrs, [:name, :description, :currency_id, :project_id, :is_current])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:currency_id)
    |> unique_current_constraint()
  end

  @doc "Marks the estimation current. Carries the partial unique index as a changeset error."
  def set_current_changeset(estimation) do
    estimation
    |> change(is_current: true)
    |> unique_current_constraint()
  end

  # `estimations_unique_current_per_project` is a partial unique index on
  # (project_id) WHERE is_current AND deleted_at IS NULL (migration
  # 20260319080827). One home for its name + message.
  defp unique_current_constraint(changeset) do
    unique_constraint(changeset, :is_current,
      name: :estimations_unique_current_per_project,
      message: "another estimation is already current"
    )
  end

  def update_changeset(estimation, attrs) do
    estimation
    |> cast(attrs, [:name, :description, :currency_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:currency_id)
  end

  def soft_delete_changeset(estimation) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(estimation, deleted_at: now, is_current: false)
  end
end
