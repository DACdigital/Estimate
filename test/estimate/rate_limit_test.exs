defmodule Estimate.RateLimitTest do
  use ExUnit.Case, async: true

  alias Estimate.RateLimit

  test "allows up to the limit then denies with retry ms" do
    key = "rl-test-#{System.unique_integer([:positive])}"
    for n <- 1..5, do: assert({:allow, ^n} = RateLimit.check(:totp_attempt, key))
    assert {:deny, ms} = RateLimit.check(:totp_attempt, key)
    assert ms > 0
  end

  test "retry_seconds rounds up" do
    assert RateLimit.retry_seconds(1) == 1
    assert RateLimit.retry_seconds(1_001) == 2
  end

  test "the cache key is hashed, so an unbounded input doesn't blow up the table" do
    huge = String.duplicate("a", 1_000_000) <> "@x.com"
    normal = "normal-#{System.unique_integer([:positive])}@x.com"

    assert {:allow, 1} = RateLimit.check(:login_email, huge)
    assert {:allow, 1} = RateLimit.check(:login_email, normal)
  end

  test "normalize still collides equivalent keys after hashing" do
    suffix = System.unique_integer([:positive])
    upper = "A@x-#{suffix}.com"
    lower = "a@x-#{suffix}.com"

    assert {:allow, 1} = RateLimit.check(:login_email, upper)
    assert {:allow, 2} = RateLimit.check(:login_email, lower)
  end

  test "reset/2 zeroes the counter for a bucket/key" do
    key = "reset-test-#{System.unique_integer([:positive])}"
    assert {:allow, 1} = RateLimit.check(:totp_attempt, key)
    assert {:allow, 2} = RateLimit.check(:totp_attempt, key)

    assert :ok = RateLimit.reset(:totp_attempt, key)

    assert {:allow, 1} = RateLimit.check(:totp_attempt, key)
  end
end
