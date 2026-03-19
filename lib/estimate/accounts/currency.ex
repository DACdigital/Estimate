defmodule Estimate.Accounts.Currency do
  use Estimate.Schema
  import Ecto.Changeset

  schema "currencies" do
    field :code, :string
    field :name, :string
    field :symbol, :string
    field :symbol_position, :string, default: "prefix"
    field :exchange_rate, :decimal, default: Decimal.new("1.0")
    field :is_main, :boolean, default: false

    belongs_to :organization, Estimate.Accounts.Organization

    timestamps()
  end

  def changeset(currency, attrs) do
    currency
    |> cast(attrs, [
      :code,
      :name,
      :symbol,
      :symbol_position,
      :exchange_rate,
      :is_main,
      :organization_id
    ])
    |> validate_required([:code, :name, :symbol, :organization_id])
    |> validate_length(:code, is: 3)
    |> validate_inclusion(:symbol_position, ["prefix", "suffix"])
    |> validate_number(:exchange_rate, greater_than: 0)
    |> validate_main_currency_rate()
    |> unique_constraint([:organization_id, :code])
    |> update_change(:code, &String.upcase/1)
  end

  defp validate_main_currency_rate(changeset) do
    if get_field(changeset, :is_main) do
      case get_field(changeset, :exchange_rate) do
        %Decimal{} = rate ->
          if Decimal.equal?(rate, Decimal.new("1.0")),
            do: changeset,
            else: add_error(changeset, :exchange_rate, "must be 1.0 for main currency")

        _ ->
          changeset
      end
    else
      changeset
    end
  end

  def default_currencies do
    [
      %{
        code: "USD",
        name: "US Dollar",
        symbol: "$",
        symbol_position: "prefix",
        exchange_rate: Decimal.new("1.0"),
        is_main: true
      },
      %{
        code: "EUR",
        name: "Euro",
        symbol: "€",
        symbol_position: "prefix",
        exchange_rate: Decimal.new("0.92")
      },
      %{
        code: "GBP",
        name: "British Pound",
        symbol: "£",
        symbol_position: "prefix",
        exchange_rate: Decimal.new("0.79")
      },
      %{
        code: "PLN",
        name: "Polish Zloty",
        symbol: "zł",
        symbol_position: "suffix",
        exchange_rate: Decimal.new("4.0")
      }
    ]
  end
end
