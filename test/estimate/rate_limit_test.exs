defmodule Estimate.RateLimitTest do
  use ExUnit.Case, async: true

  alias Estimate.RateLimit

  test "allows up to the limit then denies with retry ms" do
    key = "rl-test-#{System.unique_integer([:positive])}"
    for n <- 1..5, do: assert({:allow, ^n} = RateLimit.check(:totp_attempt, key))
    assert {:deny, ms} = RateLimit.check(:totp_attempt, key)
    assert ms > 0
  end

  test "totp_replay allows a code once per user" do
    user_id = Ecto.UUID.generate()
    assert {:allow, 1} = RateLimit.check(:totp_replay, {user_id, "123456"})
    assert {:deny, _} = RateLimit.check(:totp_replay, {user_id, "123456"})
    assert {:allow, 1} = RateLimit.check(:totp_replay, {user_id, "654321"})
  end

  test "retry_seconds rounds up" do
    assert RateLimit.retry_seconds(1) == 1
    assert RateLimit.retry_seconds(1_001) == 2
  end
end
