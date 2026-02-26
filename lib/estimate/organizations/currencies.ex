defmodule Estimate.Organizations.Currencies do
  @moduledoc """
  Context for organization currency management.
  """

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.Accounts.Currency
  alias Estimate.Accounts.Organization

  def list_currencies(org_id) do
    Repo.ensure_org_context(fn ->
      from(c in Currency,
        where: c.organization_id == ^org_id,
        order_by: [desc: c.is_main, asc: c.code]
      )
      |> Repo.all()
    end)
  end

  def get_currency!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(c in Currency,
        where: c.id == ^id and c.organization_id == ^org_id
      )
      |> Repo.one!()
    end)
  end

  def get_main_currency(org_id) do
    Repo.ensure_org_context(fn ->
      from(c in Currency,
        where: c.organization_id == ^org_id and c.is_main == true
      )
      |> Repo.one()
    end)
  end

  def set_main_currency(%Currency{} = currency) do
    Repo.ensure_org_context(fn ->
      new_main_rate = currency.exchange_rate

      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :unset_main,
        from(c in Currency, where: c.organization_id == ^currency.organization_id),
        set: [is_main: false]
      )
      |> Ecto.Multi.update(
        :set_main,
        Currency.changeset(currency, %{is_main: true, exchange_rate: Decimal.new(1)})
      )
      |> Ecto.Multi.update_all(
        :recalc_rates,
        from(c in Currency,
          where: c.organization_id == ^currency.organization_id and c.id != ^currency.id
        ),
        set: [
          exchange_rate:
            dynamic([c], fragment("ROUND(? / ?, 6)", c.exchange_rate, ^new_main_rate))
        ]
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{set_main: currency}} -> {:ok, currency}
        {:error, _op, changeset, _} -> {:error, changeset}
      end
    end)
  end

  def create_currency(org_id, attrs) do
    Repo.ensure_org_context(fn ->
      %Currency{}
      |> Currency.changeset(Map.put(attrs, :organization_id, org_id))
      |> Repo.insert()
    end)
  end

  def update_currency(%Currency{} = currency, attrs) do
    Repo.ensure_org_context(fn ->
      currency
      |> Currency.changeset(attrs)
      |> Repo.update()
    end)
  end

  def delete_currency(%Currency{} = currency) do
    Repo.ensure_org_context(fn ->
      if currency.is_main do
        {:error, :is_main_currency}
      else
        Repo.delete(currency)
      end
    end)
  end

  def change_currency(%Currency{} = currency, attrs \\ %{}) do
    Currency.changeset(currency, attrs)
  end

  def fetch_and_apply_rates(org_id) do
    Repo.ensure_org_context(fn ->
      currencies = list_currencies(org_id)
      main = Enum.find(currencies, & &1.is_main)
      others = Enum.reject(currencies, & &1.is_main)

      if main && others != [] do
        target_codes = Enum.map(others, & &1.code)

        case Estimate.ExchangeRates.fetch_rates(main.code, target_codes) do
          {:ok, rates} ->
            updated_count =
              Enum.count(others, fn currency ->
                case Map.get(rates, currency.code) do
                  nil ->
                    false

                  rate ->
                    from(c in Currency, where: c.id == ^currency.id)
                    |> Repo.update_all(set: [exchange_rate: rate])

                    true
                end
              end)

            now = DateTime.truncate(DateTime.utc_now(), :second)

            from(o in Organization, where: o.id == ^org_id)
            |> Repo.update_all(set: [rates_fetched_at: now])

            {:ok, %{fetched_at: now, updated_count: updated_count}}

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:ok, %{fetched_at: nil, updated_count: 0}}
      end
    end)
  end
end
