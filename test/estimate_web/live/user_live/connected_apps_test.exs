defmodule EstimateWeb.UserLive.ConnectedAppsTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  alias Estimate.MCP.OAuth
  alias Estimate.Organizations

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  defp grant(user, org) do
    {:ok, client} =
      OAuth.register_client(%{
        "client_name" => "Claude",
        "redirect_uris" => ["https://claude.ai/cb"]
      })

    {:ok, code} =
      OAuth.create_code(%{
        client_id: client.id,
        user_id: user.id,
        organization_id: org.id,
        redirect_uri: "https://claude.ai/cb",
        code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        resource: "http://localhost:4000/mcp",
        scope: "mcp:read mcp:write"
      })

    {:ok, tokens} =
      OAuth.exchange_code(code, %{
        client_id: client.id,
        redirect_uri: "https://claude.ai/cb",
        code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        resource: "http://localhost:4000/mcp"
      })

    tokens
  end

  setup %{conn: conn} do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    %{conn: log_in_user(conn, user), user: user, org: org}
  end

  test "empty state", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/account")
    assert html =~ "Connected apps"
    assert html =~ "No connected apps."
  end

  test "lists grants and revokes one after confirmation", %{conn: conn, user: user, org: org} do
    tokens = grant(user, org)
    {:ok, lv, html} = live(conn, ~p"/account")
    assert html =~ "Claude"
    assert html =~ org.name
    assert html =~ "Read and write"

    [g] = OAuth.list_grants(user.id)
    render_click(lv, "confirm_revoke_grant", %{"family-id" => g.family_id})
    assert assigns(lv).revoking_family_id == g.family_id

    render_click(lv, "revoke_grant", %{})
    assert assigns(lv).revoking_family_id == nil
    assert render(lv) =~ "No connected apps."
    assert {:error, :invalid_key} = OAuth.verify_access_token(tokens.access_token)
  end

  test "revoking a family that is not mine is a no-op with Not found", %{conn: conn} do
    %{user: other, organization: org2} = user_with_organization_fixture()
    {:ok, org2} = Organizations.update_mcp_settings(org2, %{mcp_enabled: true})
    tokens = grant(other, org2)
    [g] = OAuth.list_grants(other.id)

    {:ok, lv, _} = live(conn, ~p"/account")
    render_click(lv, "confirm_revoke_grant", %{"family-id" => g.family_id})
    render_click(lv, "revoke_grant", %{})
    assert render(lv) =~ "Not found"
    assert {:ok, %{}} = OAuth.verify_access_token(tokens.access_token)
  end
end
