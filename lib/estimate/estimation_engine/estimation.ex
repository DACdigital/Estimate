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
  end

  def soft_delete_changeset(estimation) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(estimation, deleted_at: now, is_current: false)
  end
end
