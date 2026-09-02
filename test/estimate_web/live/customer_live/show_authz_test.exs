defmodule EstimateWeb.CustomerLive.ShowAuthzTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, CRMFixtures}

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  test "non-admin member cannot open the delete confirmation", %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    _ = owner

    {:ok, lv, _} = live(log_in_user(conn, member), ~p"/org/#{org.id}/customers/#{customer.id}")
    render_click(lv, "confirm_delete", %{})

    refute assigns(lv).deleting_customer
    assert render(lv) =~ "Not authorized"
  end
end
