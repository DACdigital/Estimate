defmodule Estimate.Accounts.RoleTemplateRate do
  use Estimate.Schema
  import Ecto.Changeset

  schema "role_template_rates" do
    field :hourly_rate, :decimal, default: Decimal.new(0)

    belongs_to :role_template, Estimate.Accounts.RoleTemplate
    belongs_to :currency, Estimate.Accounts.Currency

    timestamps()
  end

  def changeset(rate, attrs) do
    rate
    |> cast(attrs, [:hourly_rate, :role_template_id, :currency_id])
    |> validate_required([:hourly_rate, :role_template_id, :currency_id])
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
    |> unique_constraint([:role_template_id, :currency_id])
  end
end
