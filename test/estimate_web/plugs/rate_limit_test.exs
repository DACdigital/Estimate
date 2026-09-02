defmodule EstimateWeb.Plugs.RateLimitTest do
  use ExUnit.Case, async: true

  alias EstimateWeb.Plugs.RateLimit

  test "init/1 accepts every known bucket" do
    for bucket <- Estimate.RateLimit.buckets() do
      assert RateLimit.init(bucket: bucket) == bucket
    end
  end

  test "init/1 raises ArgumentError for an unknown bucket" do
    assert_raise ArgumentError, ~r/unknown Estimate.RateLimit bucket/i, fn ->
      RateLimit.init(bucket: :not_a_real_bucket)
    end
  end
end
