defmodule Estimate.Templates.EstimationTemplateEpic do
  use Estimate.Schema
  import Ecto.Changeset

  schema "estimation_template_epics" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0

    belongs_to :estimation_template, Estimate.Templates.EstimationTemplate

    has_many :tasks, Estimate.Templates.EstimationTemplateTask, preload_order: [asc: :position]

    timestamps()
  end

  def changeset(epic, attrs) do
    epic
    |> cast(attrs, [:name, :description, :position, :estimation_template_id])
    |> validate_required([:name, :estimation_template_id])
    |> validate_length(:name, min: 1, max: 200)
  end
end
