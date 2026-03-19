defmodule Estimate.Portfolio.Project do
  use Estimate.Schema
  import Ecto.Changeset

  @statuses ~w(active archived completed)

  schema "projects" do
    field :name, :string
    field :key, :string
    field :short_description, :string
    field :detailed_description, :string
    field :repository_url, :string
    field :status, :string, default: "active"

    belongs_to :customer, Estimate.CRM.Customer
    belongs_to :currency, Estimate.Accounts.Currency
    belongs_to :organization, Estimate.Accounts.Organization
    has_many :collaborators, Estimate.Portfolio.ProjectCollaborator
    has_many :users, through: [:collaborators, :user]
    has_many :estimations, Estimate.EstimationEngine.Estimation
    has_many :roles, Estimate.Portfolio.ProjectRole

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :key,
      :short_description,
      :detailed_description,
      :repository_url,
      :status,
      :customer_id,
      :currency_id
    ])
    |> validate_required([:name, :customer_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:key, min: 2, max: 10)
    |> validate_format(:key, ~r/^[A-Z0-9]+$/,
      message: "must be uppercase letters and numbers only"
    )
    |> validate_format(:repository_url, ~r/^https?:\/\//,
      message: "must start with http:// or https://"
    )
    |> foreign_key_constraint(:currency_id)
    |> unique_constraint([:customer_id, :key])
    |> update_change(:key, fn
      nil -> nil
      val -> String.upcase(val)
    end)
  end

  def statuses, do: @statuses

  @doc """
  Returns composite key in format "CUSTOMER_KEY-PROJECT_KEY"
  """
  def composite_key(%__MODULE__{key: key, customer: %{key: customer_key}}) when not is_nil(key) do
    "#{customer_key}-#{key}"
  end

  def composite_key(_), do: nil
end
