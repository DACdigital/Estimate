defmodule Estimate.EstimationEngine.Epic do
  use Estimate.Schema
  import Ecto.Changeset

  schema "epics" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0

    belongs_to :estimation, Estimate.EstimationEngine.Estimation
    has_many :tasks, Estimate.EstimationEngine.Task

    timestamps()
  end

  def changeset(epic, attrs) do
    epic
    |> cast(attrs, [:name, :description, :position, :estimation_id])
    |> validate_required([:name, :estimation_id])
    |> validate_length(:name, min: 1, max: 200)
  end

  def update_changeset(epic, attrs) do
    epic
    |> cast(attrs, [:name, :description, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end
end
