defmodule Estimate.EstimationEngine.TaskEstimate do
  use Estimate.Schema
  import Ecto.Changeset

  schema "task_estimates" do
    field :hours, :decimal, default: Decimal.new(0)

    belongs_to :task, Estimate.EstimationEngine.Task
    belongs_to :estimation_role, Estimate.EstimationEngine.EstimationRole

    timestamps()
  end

  def changeset(estimate, attrs) do
    estimate
    |> cast(attrs, [:hours, :task_id, :estimation_role_id])
    |> validate_required([:task_id, :estimation_role_id])
    |> validate_number(:hours, greater_than_or_equal_to: 0)
    |> unique_constraint([:task_id, :estimation_role_id])
  end
end
