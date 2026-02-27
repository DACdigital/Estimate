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

  def list_customers(org_id, opts) when is_list(opts) do
    Repo.ensure_org_context(fn ->
      from(c in Customer,
        where: c.organization_id == ^org_id,
        order_by: [asc: c.name],
        preload: [:default_currency]
      )
      |> maybe_filter_watchtower(Keyword.get(opts, :watchtower))
      |> Repo.all()
    end)
  end

  defp maybe_filter_watchtower(query, nil), do: query

  defp maybe_filter_watchtower(query, :missing_description) do
    where_missing_description(query)
  end

  defp maybe_filter_watchtower(query, _), do: query

  defp where_missing_description(query) do
    from(c in query, where: is_nil(c.description) or c.description == "")
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
        |> Customer.changeset(attrs)
        |> Ecto.Changeset.put_change(:organization_id, org_id)
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
      Search.remove_index_for_customer(customer.id)

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

  def count_customers_missing_description(org_id) do
    Repo.ensure_org_context(fn ->
      from(c in Customer, where: c.organization_id == ^org_id)
      |> where_missing_description()
      |> Repo.aggregate(:count)
    end)
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end
end
