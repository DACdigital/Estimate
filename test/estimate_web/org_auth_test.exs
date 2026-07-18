defmodule EstimateWeb.OrgAuthTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  alias Estimate.Accounts.User
  alias Estimate.Repo

  describe "activity touch on org mount" do
    test "updates last activity synchronously during mount (no detached DB task)", %{conn: conn} do
      %{user: user, organization: org} = user_with_organization_fixture()
      assert is_nil(user.last_org_id)

      {:ok, _lv, _html} = live(log_in_user(conn, user), ~p"/org/#{org.id}")

      # With inline execution in the test env, the activity update has already
      # committed by the time mount returns — no reliance on a detached, unsandboxed
      # Task racing the SQL sandbox. A bare Task.start would leave this unset here.
      reloaded = Repo.get!(User, user.id)
      assert reloaded.last_org_id == org.id
      assert reloaded.last_active_at != nil
    end
  end
end
