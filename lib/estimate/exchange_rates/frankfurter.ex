defmodule Estimate.ExchangeRates.Frankfurter do
  @behaviour Estimate.ExchangeRates

  @base_url "https://api.frankfurter.dev/v1/latest"

  @impl true
  def fetch_rates(base, targets) when is_list(targets) and targets != [] do
    symbols = Enum.join(targets, ",")
    url = "#{@base_url}?base=#{base}&symbols=#{symbols}"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"rates" => rates}}} ->
        decimal_rates =
          Map.new(rates, fn {code, rate} ->
            {code, Decimal.new(to_string(rate))}
          end)

        {:ok, decimal_rates}

      {:ok, %{status: status, body: body}} ->
        {:error, "Frankfurter #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def fetch_rates(_base, []), do: {:ok, %{}}
end
