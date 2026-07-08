defmodule EstimateWeb.FormatTest do
  use ExUnit.Case, async: true

  alias EstimateWeb.Format

  defp dec(n), do: Decimal.new(n)

  describe "format_cost/2" do
    test "zero renders a dash" do
      assert Format.format_cost(dec(0), nil) == "-"
    end

    test "prefix currency (nil → $)" do
      assert Format.format_cost(dec(1500), nil) =~ "$"
      assert Format.format_cost(dec(1500), nil) =~ "1,500"
    end

    test "suffix currency appends the symbol" do
      currency = %{symbol: "zł", symbol_position: "suffix"}
      result = Format.format_cost(dec(1500), currency)
      assert String.ends_with?(result, "zł")
      assert result =~ "1,500"
    end
  end

  describe "format_rate/2" do
    test "nil currency uses $ prefix" do
      assert Format.format_rate(120, nil) == "$120/h"
    end

    test "prefix currency" do
      assert Format.format_rate(120, %{symbol: "€", symbol_position: "prefix"}) == "€120/h"
    end

    test "suffix currency" do
      assert Format.format_rate(120, %{symbol: "zł", symbol_position: "suffix"}) == "120zł/h"
    end
  end

  describe "format_hours/1" do
    test "zero → empty string" do
      assert Format.format_hours(dec(0)) == ""
    end

    test "whole → integer string" do
      assert Format.format_hours(dec(5)) == "5"
    end

    test "fractional → one decimal place" do
      assert Format.format_hours(Decimal.new("5.5")) == "5.5"
    end
  end

  describe "format_hours_with_unit/1" do
    test "zero → 0h" do
      assert Format.format_hours_with_unit(dec(0)) == "0h"
    end

    test "whole → one-decimal with h suffix" do
      assert Format.format_hours_with_unit(dec(5)) == "5.0h"
    end

    test "fractional → one-decimal with h suffix" do
      assert Format.format_hours_with_unit(Decimal.new("5.5")) == "5.5h"
    end
  end

  describe "format_percent/1" do
    test "rounds to whole integer" do
      assert Format.format_percent(Decimal.new("15.4")) == 15
      assert Format.format_percent(Decimal.new("15.6")) == 16
    end
  end

  describe "parse_decimal/1" do
    test "parses a numeric string" do
      assert Decimal.equal?(Format.parse_decimal("12.5"), Decimal.new("12.5"))
    end

    test "garbage → 0" do
      assert Decimal.equal?(Format.parse_decimal("abc"), dec(0))
    end

    test "nil → 0" do
      assert Decimal.equal?(Format.parse_decimal(nil), dec(0))
    end

    test "number input" do
      assert Decimal.equal?(Format.parse_decimal(7), dec(7))
    end
  end

  describe "parse_decimal/2" do
    test "nil → supplied default" do
      assert Format.parse_decimal(nil, :fallback) == :fallback
    end

    test "empty string → supplied default" do
      assert Format.parse_decimal("", :fallback) == :fallback
    end

    test "valid string → parsed decimal" do
      assert Decimal.equal?(Format.parse_decimal("9.9", dec(0)), Decimal.new("9.9"))
    end

    test "invalid string → supplied default" do
      assert Format.parse_decimal("nope", :fallback) == :fallback
    end

    test "non-string value (e.g. a Decimal) passes through unchanged" do
      assert Decimal.equal?(Format.parse_decimal(Decimal.new("3.3"), :fallback), Decimal.new("3.3"))
    end
  end

  describe "decimal_to_number/1" do
    test "whole → integer" do
      assert Format.decimal_to_number(dec(10)) === 10
    end

    test "fractional → float" do
      assert Format.decimal_to_number(Decimal.new("10.5")) === 10.5
    end
  end
end
