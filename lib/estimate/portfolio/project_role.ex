defmodule Estimate.Portfolio.ProjectRole do
  use Estimate.Schema
  import Ecto.Changeset

  schema "project_roles" do
    field :name, :string
    field :abbreviation, :string
    field :hourly_rate, :decimal, default: Decimal.new(0)
    field :position, :integer, default: 0
    field :pm_overhead, :decimal, default: Decimal.new(0)
    field :qa_overhead, :decimal, default: Decimal.new(0)
    field :risk_buffer, :decimal, default: Decimal.new(0)

    belongs_to :project, Estimate.Portfolio.Project

    timestamps()
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [
      :name,
      :abbreviation,
      :hourly_rate,
      :position,
      :pm_overhead,
      :qa_overhead,
      :risk_buffer,
      :project_id
    ])
    |> validate_required([:name, :abbreviation, :project_id])
    |> validate_length(:abbreviation, min: 1, max: 5)
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
    |> validate_number(:pm_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:qa_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:risk_buffer, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:project_id, :abbreviation])
    |> update_change(:abbreviation, &String.upcase/1)
  end
end
