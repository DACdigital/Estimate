defmodule Estimate.Repo.Migrations.SimplifyTaskEstimatesToSingleHours do
  use Ecto.Migration

  def up do
    # Add new hours column
    alter table(:task_estimates) do
      add :hours, :decimal, default: 0, null: false
    end

    # Migrate data: use average of min and max
    execute """
    UPDATE task_estimates
    SET hours = (min_hours + max_hours) / 2
    """

    # Remove old columns
    alter table(:task_estimates) do
      remove :min_hours
      remove :max_hours
    end
  end

  def down do
    # Add back old columns
    alter table(:task_estimates) do
      add :min_hours, :decimal, default: 0, null: false
      add :max_hours, :decimal, default: 0, null: false
    end

    # Migrate data back (set both to hours value)
    execute """
    UPDATE task_estimates
    SET min_hours = hours, max_hours = hours
    """

    # Remove hours column
    alter table(:task_estimates) do
      remove :hours
    end
  end
end
