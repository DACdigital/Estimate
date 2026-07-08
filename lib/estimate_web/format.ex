defmodule EstimateWeb.Format do
  @moduledoc """
  Canonical presentation formatters (currency, hours, percent, decimals).

  Consolidates formatting logic previously scattered across LiveViews and
  `EstimatorLive.Helpers`. Callers migrate onto this module cluster-by-cluster;
  once migration is complete the old copies are removed and this module is
  imported app-wide.
  """

  @doc "Formats a monetary Decimal with a currency's symbol/position. Zero → \"-\"."
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

  @doc "Formats an hourly rate like `$120/h`, honoring currency symbol position."
  def format_rate(rate, nil), do: "$#{rate}/h"

  def format_rate(rate, currency) do
    case currency.symbol_position do
      "suffix" -> "#{rate}#{currency.symbol}/h"
      _ -> "#{currency.symbol}#{rate}/h"
    end
  end

  @doc "Hours for tables: zero → \"\", whole → integer, otherwise 1 decimal place."
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

  @doc "Hours with a unit suffix: zero → \"0h\", otherwise `\"<1dp>h\"`."
  def format_hours_with_unit(decimal) do
    if Decimal.compare(decimal, 0) == :eq do
      "0h"
    else
      "#{decimal |> Decimal.round(1) |> Decimal.to_string()}h"
    end
  end

  @doc "Rounds a percentage Decimal to a whole integer."
  def format_percent(decimal), do: decimal |> Decimal.round(0) |> Decimal.to_integer()

  @doc "Parses a value to Decimal, defaulting to 0 on any failure."
  def parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      {decimal, remainder} -> if String.trim(remainder) == "", do: decimal, else: Decimal.new(0)
      :error -> Decimal.new(0)
    end
  end

  def parse_decimal(value) when is_number(value), do: Decimal.new(value)
  def parse_decimal(_), do: Decimal.new(0)

  @doc "Parses a value to Decimal, returning `default` on nil/empty/failure."
  def parse_decimal(nil, default), do: default
  def parse_decimal("", default), do: default

  def parse_decimal(value, default) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> default
    end
  end

  def parse_decimal(value, _default), do: value

  @doc "Converts a Decimal to an integer when whole, otherwise a float."
  def decimal_to_number(decimal) do
    if Decimal.equal?(Decimal.rem(decimal, 1), 0) do
      Decimal.to_integer(decimal)
    else
      Decimal.to_float(decimal)
    end
  end
end
