defmodule Estimate.CRM do
  @moduledoc """
  The CRM context for managing customers.
  """

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.CRM.Customer
  alias Estimate.Search

  def list_customers(org_id) do
    Repo.ensure_org_context(fn ->
      from(c in Customer,
        where: c.organization_id == ^org_id,
        order_by: [asc: c.name],
        preload: [:default_currency]
      )
      |> Repo.all()
    end)
  end

  def get_customer!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(c in Customer,
        where: c.id == ^id and c.organization_id == ^org_id,
        preload: [:default_currency]
      )
      |> Repo.one!()
    end)
  end

  def create_customer(org_id, attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %Customer{}
        |> Customer.changeset(Map.put(attrs, "organization_id", org_id))
        |> Repo.insert()

      case result do
        {:ok, customer} ->
          Search.index_customer(customer)
          {:ok, customer}

        error ->
          error
      end
    end)
  end

  def update_customer(%Customer{} = customer, attrs) do
    Repo.ensure_org_context(fn ->
      result =
        customer
        |> Customer.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, customer} ->
          Search.index_customer(customer)
          {:ok, customer}

        error ->
          error
      end
    end)
  end

  def delete_customer(%Customer{} = customer) do
    Repo.ensure_org_context(fn ->
      result = Repo.delete(customer)

      case result do
        {:ok, customer} ->
          Search.remove_index("customer", customer.id)
          {:ok, customer}

        error ->
          error
      end
    end)
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end
end
