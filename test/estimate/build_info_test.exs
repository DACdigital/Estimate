defmodule Estimate.BuildInfoTest do
  # async: false — mutates the GIT_SHA process-global env var
  use ExUnit.Case, async: false

  alias Estimate.BuildInfo

  setup do
    original = System.get_env("GIT_SHA")

    on_exit(fn ->
      case original do
        nil -> System.delete_env("GIT_SHA")
        value -> System.put_env("GIT_SHA", value)
      end
    end)

    :ok
  end

  test "falls back to the local git checkout sha" do
    System.delete_env("GIT_SHA")

    sha = BuildInfo.git_sha()

    assert is_binary(sha)
    assert sha =~ ~r/^[0-9a-f]{7,}$/
  end

  test "runtime GIT_SHA env takes precedence over the local fallback" do
    System.put_env("GIT_SHA", "abc1234")

    assert BuildInfo.git_sha() == "abc1234"
  end

  test "empty GIT_SHA env is treated as absent" do
    System.put_env("GIT_SHA", "")

    sha = BuildInfo.git_sha()

    assert sha != ""
    assert sha =~ ~r/^[0-9a-f]{7,}$/
  end
end
