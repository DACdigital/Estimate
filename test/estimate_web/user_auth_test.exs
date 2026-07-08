defmodule EstimateWeb.UserAuthTest do
  use ExUnit.Case, async: true

  alias EstimateWeb.UserAuth

  describe "safe_return_to/1" do
    test "accepts simple local paths" do
      assert UserAuth.safe_return_to("/org/123") == "/org/123"
      assert UserAuth.safe_return_to("/projects/abc/estimations") == "/projects/abc/estimations"
    end

    test "rejects protocol-relative URLs (open redirect)" do
      assert UserAuth.safe_return_to("//evil.com") == nil
      assert UserAuth.safe_return_to("/\\evil.com") == nil
    end

    test "rejects absolute URLs with scheme/host" do
      assert UserAuth.safe_return_to("https://evil.com") == nil
      assert UserAuth.safe_return_to("http://evil.com/path") == nil
    end

    test "rejects paths without a leading slash" do
      assert UserAuth.safe_return_to("evil.com") == nil
      assert UserAuth.safe_return_to("javascript:alert(1)") == nil
    end

    test "rejects non-string input" do
      assert UserAuth.safe_return_to(nil) == nil
      assert UserAuth.safe_return_to(%{}) == nil
    end
  end
end
