defmodule Estimate.RateLimit do
  @moduledoc """
  Fixed-window rate limiting for auth-sensitive endpoints, backed by Hammer's ETS store.

  Limits are read from `config :estimate, Estimate.RateLimit` so the test env can
  raise IP-scoped limits (every test shares 127.0.0.1).
  """
  use Hammer, backend: :ets

  @windows %{
    login_email: :timer.minutes(1),
    login_ip: :timer.minutes(1),
    totp_attempt: :timer.minutes(15),
    oauth_ip: :timer.minutes(1)
  }

  @defaults %{login_email: 10, login_ip: 60, totp_attempt: 5, oauth_ip: 20}

  @type bucket :: :login_email | :login_ip | :totp_attempt | :oauth_ip

  @spec buckets() :: [bucket()]
  def buckets, do: Map.keys(@windows)

  @spec check(bucket(), term()) :: {:allow, pos_integer()} | {:deny, pos_integer()}
  def check(bucket, key) when is_map_key(@windows, bucket) do
    hit(cache_key(bucket, key), Map.fetch!(@windows, bucket), limit(bucket))
  end

  @doc "Zeroes the counter for `bucket`/`key`, e.g. so a successful login clears a failed-attempt count."
  @spec reset(bucket(), term()) :: :ok
  def reset(bucket, key) when is_map_key(@windows, bucket) do
    set(cache_key(bucket, key), Map.fetch!(@windows, bucket), 0)
    :ok
  end

  @spec retry_seconds(pos_integer()) :: pos_integer()
  def retry_seconds(ms), do: max(div(ms + 999, 1000), 1)

  # Keys are hashed so that unbounded client-controlled input (an arbitrarily long
  # email, say) can't be used to grow unbounded ETS keys/memory.
  defp cache_key(bucket, key), do: "#{bucket}:" <> hash(normalize(key))

  defp hash(term), do: :crypto.hash(:sha256, term) |> Base.encode16(case: :lower)

  defp limit(bucket) do
    :estimate
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(bucket, Map.fetch!(@defaults, bucket))
  end

  defp normalize(key) when is_binary(key), do: String.downcase(key)
  defp normalize(key), do: to_string(key)
end
