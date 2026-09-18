defmodule Estimate.RepoEachOkTest do
  use ExUnit.Case, async: true

  alias Estimate.Repo

  test "returns :ok when every call succeeds (accepting :ok or {:ok, _})" do
    assert Repo.each_ok([1, 2, 3], fn
             1 -> :ok
             n -> {:ok, n}
           end) == :ok
  end

  test "stops at the first error and returns it" do
    seen = :counters.new(1, [])

    result =
      Repo.each_ok([1, 2, 3], fn n ->
        :counters.add(seen, 1, 1)
        if n == 2, do: {:error, {:bad, n}}, else: :ok
      end)

    assert result == {:error, {:bad, 2}}
    assert :counters.get(seen, 1) == 2
  end

  test "empty input is :ok" do
    assert Repo.each_ok([], fn _ -> flunk("must not be called") end) == :ok
  end
end
