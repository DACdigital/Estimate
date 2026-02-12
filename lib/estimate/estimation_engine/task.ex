defmodule Estimate.EstimationEngine.Task do
  use Estimate.Schema
  import Ecto.Changeset

  @priorities ~w(must should could wont)

  schema "tasks" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0
    field :priority, :string, default: "must"

    belongs_to :epic, Estimate.EstimationEngine.Epic
    has_many :estimates, Estimate.EstimationEngine.TaskEstimate

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :description, :position, :priority, :epic_id])
    |> validate_required([:name, :epic_id])
    |> validate_length(:name, min: 1, max: 500)
    |> validate_inclusion(:priority, @priorities)
  end

  def priorities, do: @priorities

  def priority_label("must"), do: "Must"
  def priority_label("should"), do: "Should"
  def priority_label("could"), do: "Could"
  def priority_label("wont"), do: "Won't"
  def priority_label(_), do: "Must"
end
