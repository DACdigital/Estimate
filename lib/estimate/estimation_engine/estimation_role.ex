defmodule Estimate.EstimationEngine.EstimationRole do
  use Estimate.Schema
  import Ecto.Changeset

  schema "estimation_roles" do
    field :name, :string
    field :abbreviation, :string
    field :hourly_rate, :decimal, default: Decimal.new(0)
    field :position, :integer, default: 0
    field :pm_overhead, :decimal, default: Decimal.new(0)
    field :qa_overhead, :decimal, default: Decimal.new(0)
    field :risk_buffer, :decimal, default: Decimal.new(0)

    belongs_to :estimation, Estimate.EstimationEngine.Estimation
    belongs_to :project_role, Estimate.Portfolio.ProjectRole
    has_many :task_estimates, Estimate.EstimationEngine.TaskEstimate

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
      :estimation_id,
      :project_role_id
    ])
    |> validate_required([:name, :abbreviation, :estimation_id])
    |> validate_length(:abbreviation, min: 1, max: 5)
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
    |> validate_number(:pm_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:qa_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:risk_buffer, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end

  def default_roles do
    Estimate.Accounts.RoleTemplate.default_templates()
    |> Enum.map(fn t ->
      %{
        name: t.name,
        abbreviation: t.abbreviation,
        hourly_rate: Decimal.new(t.default_rate),
        pm_overhead: Decimal.new(t.pm_overhead),
        qa_overhead: Decimal.new(t.qa_overhead),
        risk_buffer: Decimal.new(t.risk_buffer)
      }
    end)
  end
end
