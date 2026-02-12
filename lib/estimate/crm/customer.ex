defmodule Estimate.CRM.Customer do
  use Estimate.Schema
  import Ecto.Changeset

  schema "customers" do
    field :key, :string
    field :name, :string
    field :country, :string
    field :website_url, :string
    field :description, :string

    belongs_to :organization, Estimate.Accounts.Organization
    belongs_to :default_currency, Estimate.Accounts.Currency
    has_many :projects, Estimate.Portfolio.Project

    timestamps()
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [
      :key,
      :name,
      :country,
      :website_url,
      :description,
      :default_currency_id,
      :organization_id
    ])
    |> validate_required([:key, :name, :organization_id])
    |> validate_length(:key, min: 2, max: 20)
    |> validate_length(:name, min: 1, max: 200)
    |> validate_format(:country, ~r/^[A-Z]{2}$/,
      message: "must be 2-letter ISO code (e.g., US, DE)"
    )
    |> validate_format(:website_url, ~r/^https?:\/\//,
      message: "must start with http:// or https://"
    )
    |> unique_constraint([:organization_id, :key])
    |> update_change(:key, &String.upcase/1)
    |> update_change(:country, fn
      nil -> nil
      val -> String.upcase(val)
    end)
  end
end
