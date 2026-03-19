defmodule Estimate.EstimationEngine.Calculator do
  @moduledoc """
  Pure calculation functions for estimation costs and hours.
  All functions operate on in-memory data structures (epics, roles, tasks).
  """

  # Build a lookup map once for O(1) role access
  defp role_map(roles), do: Map.new(roles, &{&1.id, &1})

  # Task-level calculations

  def task_total_hours(task) do
    Enum.reduce(task.estimates, Decimal.new(0), fn est, acc ->
      Decimal.add(acc, est.hours)
    end)
  end

  def task_total_cost(task, roles) do
    rmap = role_map(roles)

    Enum.reduce(task.estimates, Decimal.new(0), fn est, acc ->
      case Map.get(rmap, est.estimation_role_id) do
        nil -> acc
        role -> Decimal.add(acc, Decimal.mult(est.hours, role.hourly_rate))
      end
    end)
  end

  # Epic-level calculations

  def epic_hours(epic) do
    Enum.reduce(epic.tasks, Decimal.new(0), fn task, acc ->
      Enum.reduce(task.estimates, acc, fn est, inner_acc ->
        Decimal.add(inner_acc, est.hours)
      end)
    end)
  end

  def epic_role_hours(epic, role_id) do
    Enum.reduce(epic.tasks, Decimal.new(0), fn task, acc ->
      est = Enum.find(task.estimates, &(&1.estimation_role_id == role_id))
      if est, do: Decimal.add(acc, est.hours), else: acc
    end)
  end

  def epic_base_cost(epic, roles) do
    rmap = role_map(roles)

    Enum.reduce(epic.tasks, Decimal.new(0), fn task, acc ->
      Enum.reduce(task.estimates, acc, fn est, inner_acc ->
        case Map.get(rmap, est.estimation_role_id) do
          nil -> inner_acc
          role -> Decimal.add(inner_acc, Decimal.mult(est.hours, role.hourly_rate))
        end
      end)
    end)
  end

  def epic_total_cost(epic, roles) do
    Enum.reduce(epic.tasks, Decimal.new(0), fn task, acc ->
      Decimal.add(acc, task_total_cost(task, roles))
    end)
  end

  def epic_total_with_overhead(epic, roles) do
    rmap = role_map(roles)

    Enum.reduce(epic.tasks, Decimal.new(0), fn task, acc ->
      Enum.reduce(task.estimates, acc, fn est, inner_acc ->
        case Map.get(rmap, est.estimation_role_id) do
          nil ->
            inner_acc

          role ->
            base = Decimal.mult(est.hours, role.hourly_rate)
            pm = Decimal.mult(base, Decimal.div(role.pm_overhead, 100))
            qa = Decimal.mult(base, Decimal.div(role.qa_overhead, 100))
            risk = Decimal.mult(base, Decimal.div(role.risk_buffer, 100))

            Decimal.add(
              inner_acc,
              base |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk)
            )
        end
      end)
    end)
  end

  # Grand totals (across all epics)

  def calc_total_hours(epics) do
    Enum.reduce(epics, Decimal.new(0), fn epic, acc ->
      Decimal.add(acc, epic_hours(epic))
    end)
  end

  def calc_base_cost(epics, roles) do
    rmap = role_map(roles)

    Enum.reduce(epics, Decimal.new(0), fn epic, acc ->
      Enum.reduce(epic.tasks, acc, fn task, inner_acc ->
        Enum.reduce(task.estimates, inner_acc, fn est, est_acc ->
          case Map.get(rmap, est.estimation_role_id) do
            nil -> est_acc
            role -> Decimal.add(est_acc, Decimal.mult(est.hours, role.hourly_rate))
          end
        end)
      end)
    end)
  end

  def calc_overhead_hours(epics, roles, overhead_field) do
    rmap = role_map(roles)

    Enum.reduce(epics, Decimal.new(0), fn epic, acc ->
      Enum.reduce(epic.tasks, acc, fn task, inner_acc ->
        Enum.reduce(task.estimates, inner_acc, fn est, est_acc ->
          case Map.get(rmap, est.estimation_role_id) do
            nil ->
              est_acc

            role ->
              percent = Map.get(role, overhead_field) |> Decimal.div(100)
              Decimal.add(est_acc, Decimal.mult(est.hours, percent))
          end
        end)
      end)
    end)
  end

  def calc_overhead_cost(epics, roles, overhead_field) do
    rmap = role_map(roles)

    Enum.reduce(epics, Decimal.new(0), fn epic, acc ->
      Enum.reduce(epic.tasks, acc, fn task, inner_acc ->
        Enum.reduce(task.estimates, inner_acc, fn est, est_acc ->
          case Map.get(rmap, est.estimation_role_id) do
            nil ->
              est_acc

            role ->
              base = Decimal.mult(est.hours, role.hourly_rate)
              percent = Map.get(role, overhead_field) |> Decimal.div(100)
              Decimal.add(est_acc, Decimal.mult(base, percent))
          end
        end)
      end)
    end)
  end

  def calc_total_with_overhead_hours(epics, roles) do
    base = calc_total_hours(epics)
    pm = calc_overhead_hours(epics, roles, :pm_overhead)
    qa = calc_overhead_hours(epics, roles, :qa_overhead)
    risk = calc_overhead_hours(epics, roles, :risk_buffer)
    base |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk)
  end

  def calc_total_with_overhead_cost(epics, roles) do
    base = calc_base_cost(epics, roles)
    pm = calc_overhead_cost(epics, roles, :pm_overhead)
    qa = calc_overhead_cost(epics, roles, :qa_overhead)
    risk = calc_overhead_cost(epics, roles, :risk_buffer)
    base |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk)
  end

  # Role-level calculations

  def role_hours(epics, role_id) do
    Enum.reduce(epics, Decimal.new(0), fn epic, acc ->
      Enum.reduce(epic.tasks, acc, fn task, inner_acc ->
        est = Enum.find(task.estimates, &(&1.estimation_role_id == role_id))
        if est, do: Decimal.add(inner_acc, est.hours), else: inner_acc
      end)
    end)
  end

  def role_base_cost(epics, role) do
    hours = role_hours(epics, role.id)
    Decimal.mult(hours, role.hourly_rate)
  end

  def role_overhead_hours(base_hours, overhead_percent) do
    Decimal.mult(base_hours, Decimal.div(overhead_percent, 100))
  end

  def role_overhead_cost(base_cost, overhead_percent) do
    Decimal.mult(base_cost, Decimal.div(overhead_percent, 100))
  end

  def role_pm_overhead(epics, role), do: role_overhead(epics, role, :pm_overhead)
  def role_qa_overhead(epics, role), do: role_overhead(epics, role, :qa_overhead)
  def role_risk_buffer(epics, role), do: role_overhead(epics, role, :risk_buffer)

  defp role_overhead(epics, role, field) do
    base = role_base_cost(epics, role)
    Decimal.mult(base, Decimal.div(Map.get(role, field), 100))
  end

  # Aggregate overhead calculations

  def total_base_cost(epics, roles) do
    Enum.reduce(roles, Decimal.new(0), fn role, acc ->
      Decimal.add(acc, role_base_cost(epics, role))
    end)
  end

  def total_pm_overhead(epics, roles) do
    Enum.reduce(roles, Decimal.new(0), fn role, acc ->
      Decimal.add(acc, role_pm_overhead(epics, role))
    end)
  end

  def total_qa_overhead(epics, roles) do
    Enum.reduce(roles, Decimal.new(0), fn role, acc ->
      Decimal.add(acc, role_qa_overhead(epics, role))
    end)
  end

  def total_risk_buffer(epics, roles) do
    Enum.reduce(roles, Decimal.new(0), fn role, acc ->
      Decimal.add(acc, role_risk_buffer(epics, role))
    end)
  end

  def grand_total_with_overhead(epics, roles) do
    base = total_base_cost(epics, roles)
    pm = total_pm_overhead(epics, roles)
    qa = total_qa_overhead(epics, roles)
    risk = total_risk_buffer(epics, roles)

    base
    |> Decimal.add(pm)
    |> Decimal.add(qa)
    |> Decimal.add(risk)
  end

  # Utility functions

  def all_in_rate(role) do
    overhead_multiplier =
      Decimal.new(1)
      |> Decimal.add(Decimal.div(role.pm_overhead || Decimal.new(0), 100))
      |> Decimal.add(Decimal.div(role.qa_overhead || Decimal.new(0), 100))
      |> Decimal.add(Decimal.div(role.risk_buffer || Decimal.new(0), 100))

    Decimal.mult(role.hourly_rate, overhead_multiplier)
    |> Decimal.round(0)
  end

  def roles_with_all_in_rates(roles) do
    Enum.map(roles, fn role ->
      %{role | hourly_rate: all_in_rate(role)}
    end)
  end

  def has_overhead?(roles) do
    Enum.any?(roles, fn role ->
      Decimal.compare(role.pm_overhead, 0) == :gt ||
        Decimal.compare(role.qa_overhead, 0) == :gt ||
        Decimal.compare(role.risk_buffer, 0) == :gt
    end)
  end

  def weighted_avg_overhead(epics, roles, overhead_fn) do
    total_base = total_base_cost(epics, roles)

    if Decimal.compare(total_base, 0) == :eq do
      Decimal.new(0)
    else
      total_overhead =
        Enum.reduce(roles, Decimal.new(0), fn role, acc ->
          Decimal.add(acc, overhead_fn.(epics, role))
        end)

      total_overhead
      |> Decimal.div(total_base)
      |> Decimal.mult(100)
      |> Decimal.round(1)
    end
  end
end
