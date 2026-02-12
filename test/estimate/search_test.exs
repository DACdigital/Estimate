defmodule Estimate.SearchTest do
  use Estimate.DataCase

  alias Estimate.Search

  @fake_org_id "00000000-0000-0000-0000-000000000000"

  describe "prepare_ts_query (via search/3)" do
    test "handles special characters without crashing" do
      # Should not raise, should return empty results
      assert Search.search(@fake_org_id, "test'query") == []
      assert Search.search(@fake_org_id, "hello!world") == []
      assert Search.search(@fake_org_id, "(parens)") == []
      assert Search.search(@fake_org_id, "foo:bar") == []
    end

    test "returns empty for short queries" do
      assert Search.search(@fake_org_id, "a") == []
    end
  end
end
