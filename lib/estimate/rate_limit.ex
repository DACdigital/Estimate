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
    # Load-bearing invariant: this window is safe ONLY because 90s is a whole
    # multiple of the 30s TOTP period. Hammer's fixed windows are epoch-aligned
    # (window = div(now, scale)), and NimbleTOTP.valid?/2 accepts a single period
    # with no drift tolerance -- so a code is valid for at most one 30s period,
    # and a 90s (= 3 x 30s) window can never let two DIFFERENT periods that
    # both validate the same raw `code` string collide across a window boundary
    # in a way that reopens the replay guard early. Shrinking this below a whole
    # multiple of 30s (or changing the TOTP period without updating this) breaks
    # the guarantee.
    totp_replay: :timer.seconds(90),
    oauth_ip: :timer.minutes(1)
  }

  @defaults %{login_email: 10, login_ip: 60, totp_attempt: 5, totp_replay: 1, oauth_ip: 20}

  @type bucket :: :login_email | :login_ip | :totp_attempt | :totp_replay | :oauth_ip

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
  defp normalize({a, b}), do: "#{normalize(a)}|#{normalize(b)}"
  defp normalize(key), do: to_string(key)
end
