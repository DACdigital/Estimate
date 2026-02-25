defmodule EstimateWeb.EstimatorLive.Helpers do
  @moduledoc """
  Shared helper functions for EstimatorLive views.
  """

  alias Estimate.EstimationEngine.Calculator

  def build_json_export(estimation, display_roles, customer, project) do
    role_map = Map.new(estimation.roles, &{&1.id, &1})
    display_role_map = Map.new(display_roles, &{&1.id, &1})

    roles_json =
      Enum.map(estimation.roles, fn role ->
        dr = Map.get(display_role_map, role.id, role)

        ordered(%{
          "abbreviation" => role.abbreviation,
          "name" => role.name,
          "hourly_rate" => decimal_to_number(dr.hourly_rate)
        })
      end)

    epics_json =
      Enum.map(estimation.epics, fn epic ->
        tasks_json =
          Enum.map(epic.tasks, fn task ->
            efforts = task_efforts(task, role_map)

            ordered(%{
              "name" => task.name,
              "description" => non_empty(task.description),
              "priority" => task.priority || "must",
              "efforts" => efforts,
              "total_hours" => decimal_to_number(Calculator.task_total_hours(task)),
              "total_cost" => decimal_to_number(Calculator.task_total_cost(task, display_roles))
            })
          end)

        ordered(%{
          "name" => epic.name,
          "description" => non_empty(epic.description),
          "tasks" => tasks_json,
          "subtotal_efforts" => epic_efforts(epic, estimation.roles),
          "subtotal_hours" => decimal_to_number(Calculator.epic_hours(epic)),
          "subtotal_cost" => decimal_to_number(Calculator.epic_total_cost(epic, display_roles))
        })
      end)

    Jason.OrderedObject.new([
      {"customer", customer.name},
      {"project", project.name},
      {"estimation", estimation.name},
      {"currency", if(estimation.currency, do: estimation.currency.code, else: "USD")},
      {"roles", roles_json},
      {"epics", epics_json},
      {"total_efforts", total_efforts(estimation.epics, estimation.roles)},
      {"total_hours", decimal_to_number(Calculator.calc_total_hours(estimation.epics))},
      {"total_cost",
       decimal_to_number(Calculator.calc_base_cost(estimation.epics, display_roles))}
    ])
    |> Jason.encode!(pretty: true)
  end

  defp ordered(map) when is_map(map) do
    Jason.OrderedObject.new(Enum.sort_by(Map.to_list(map), fn {k, _} -> k end))
  end

  defp task_efforts(task, role_map) do
    Enum.reduce(task.estimates, %{}, fn est, acc ->
      case Map.get(role_map, est.estimation_role_id) do
        nil ->
          acc

        role ->
          h = decimal_to_number(est.hours)
          if h > 0, do: Map.put(acc, role.abbreviation, h), else: acc
      end
    end)
  end

  defp epic_efforts(epic, roles) do
    Enum.reduce(roles, %{}, fn role, acc ->
      h = decimal_to_number(Calculator.epic_role_hours(epic, role.id))
      if h > 0, do: Map.put(acc, role.abbreviation, h), else: acc
    end)
  end

  defp total_efforts(epics, roles) do
    Enum.reduce(roles, %{}, fn role, acc ->
      h = decimal_to_number(Calculator.role_hours(epics, role.id))
      if h > 0, do: Map.put(acc, role.abbreviation, h), else: acc
    end)
  end

  defp decimal_to_number(decimal) do
    if Decimal.equal?(Decimal.rem(decimal, 1), 0) do
      Decimal.to_integer(decimal)
    else
      Decimal.to_float(decimal)
    end
  end

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil
  defp non_empty(s), do: s

  def parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> Decimal.new(0)
    end
  end

  def parse_decimal(value) when is_number(value), do: Decimal.new(value)
  def parse_decimal(_), do: Decimal.new(0)

  def format_hours(decimal) do
    cond do
      Decimal.compare(decimal, 0) == :eq ->
        ""

      Decimal.rem(decimal, 1) |> Decimal.compare(0) == :eq ->
        decimal |> Decimal.round(0) |> Decimal.to_integer() |> to_string()

      true ->
        decimal |> Decimal.round(1) |> Decimal.to_string()
    end
  end

  def format_cost(decimal, currency) do
    if Decimal.compare(decimal, 0) == :eq do
      "-"
    else
      symbol = if currency, do: currency.symbol, else: "$"
      position = if currency, do: currency.symbol_position, else: "prefix"

      case position do
        "suffix" ->
          Number.Currency.number_to_currency(decimal, unit: "", format: "%n") <> symbol

        _ ->
          Number.Currency.number_to_currency(decimal, unit: symbol)
      end
    end
  end

  def format_rate(rate, nil), do: "$#{rate}/h"

  def format_rate(rate, currency) do
    case currency.symbol_position do
      "suffix" -> "#{rate}#{currency.symbol}/h"
      _ -> "#{currency.symbol}#{rate}/h"
    end
  end

  def format_percent(decimal), do: decimal |> Decimal.round(0) |> Decimal.to_integer()

  def priority_label("must"), do: "Must"
  def priority_label("should"), do: "Should"
  def priority_label("could"), do: "Could"
  def priority_label("wont"), do: "Won't"
  def priority_label(_), do: "Must"

  def priority_class("must"), do: "bg-error/10 dark:bg-error/20 text-error"
  def priority_class("should"), do: "bg-warning/10 dark:bg-warning/20 text-warning"
  def priority_class("could"), do: "bg-info/10 dark:bg-info/20 text-info"
  def priority_class("wont"), do: "bg-base-200 text-base-content/60"
  def priority_class(_), do: "bg-error/10 dark:bg-error/20 text-error"

  def priority_description("must"), do: "Critical for launch. Non-negotiable."
  def priority_description("should"), do: "Important but not vital. Include if possible."
  def priority_description("could"), do: "Nice to have. Include if time permits."
  def priority_description("wont"), do: "Out of scope for this release."
  def priority_description(_), do: "Critical for launch. Non-negotiable."
end
