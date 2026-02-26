defmodule Estimate.ExchangeRates do
  @callback fetch_rates(base :: String.t(), targets :: [String.t()]) ::
              {:ok, %{String.t() => Decimal.t()}} | {:error, term()}

  def fetch_rates(base, targets) do
    provider().fetch_rates(base, targets)
  end

  defp provider do
    Application.get_env(:estimate, :exchange_rate_provider, Estimate.ExchangeRates.Frankfurter)
  end
end
