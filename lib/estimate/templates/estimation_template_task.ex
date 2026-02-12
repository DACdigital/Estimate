defmodule Estimate.Templates.EstimationTemplateTask do
  use Estimate.Schema
  import Ecto.Changeset

  @priorities ~w(must should could wont)

  schema "estimation_template_tasks" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0
    field :priority, :string, default: "must"

    belongs_to :estimation_template_epic, Estimate.Templates.EstimationTemplateEpic

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :description, :position, :priority, :estimation_template_epic_id])
    |> validate_required([:name, :estimation_template_epic_id])
    |> validate_length(:name, min: 1, max: 500)
    |> validate_inclusion(:priority, @priorities)
  end

  def priorities, do: @priorities
end
