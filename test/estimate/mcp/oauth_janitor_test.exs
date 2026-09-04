defmodule Estimate.MCP.OAuth.JanitorTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.MCP.OAuth
  alias Estimate.MCP.OAuth.{Code, Janitor, Token}
  alias Estimate.Organizations

  @redirect "https://claude.ai/api/mcp/auth_callback"
  @challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  @resource "http://localhost:4000/mcp"

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})

    {:ok, client} =
      OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => [@redirect]})

    %{user: user, org: org, client: client}
  end

  defp mint(ctx) do
    {:ok, code} =
      OAuth.create_code(%{
        client_id: ctx.client.id,
        user_id: ctx.user.id,
        organization_id: ctx.org.id,
        redirect_uri: @redirect,
        code_challenge: @challenge,
        resource: @resource
      })

    {:ok, tokens} =
      OAuth.exchange_code(code, %{
        client_id: ctx.client.id,
        redirect_uri: @redirect,
        code_verifier: @verifier,
        resource: @resource
      })

    tokens
  end

  defp ago(days),
    do: DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

  test "deletes long-expired unreferenced codes and long-dead tokens, keeps live tokens and referenced codes",
       ctx do
    live = mint(ctx)
    dead = mint(ctx)
    # dead.refresh now revoked, rotated
    {:ok, _} = OAuth.refresh_tokens(dead.refresh_token, ctx.client.id)

    # an authorization code that was never exchanged: no token ever references it
    {:ok, _unused_code} =
      OAuth.create_code(%{
        client_id: ctx.client.id,
        user_id: ctx.user.id,
        organization_id: ctx.org.id,
        redirect_uri: @redirect,
        code_challenge: @challenge,
        resource: @resource
      })

    # age the revoked token row and expire every code, referenced or not
    Repo.update_all(from(t in Token, where: not is_nil(t.revoked_at)), set: [revoked_at: ago(8)])
    Repo.update_all(from(c in Code), set: [expires_at: ago(1)])

    before_tokens = Repo.aggregate(Token, :count)
    before_codes = Repo.aggregate(Code, :count)
    assert before_codes == 3

    assert %{codes: codes, tokens: 1} = Janitor.run()
    assert codes == 1
    assert Repo.aggregate(Token, :count) == before_tokens - 1
    # both exchanged codes (live's and dead's) are still referenced by a token
    # (dead's via its post-rotation replacement) and survive despite expiry
    assert Repo.aggregate(Code, :count) == before_codes - 1
    assert {:ok, %{}} = OAuth.verify_access_token(live.access_token)
  end

  test "a token revoked less than 7 days ago is kept", ctx do
    t = mint(ctx)
    {:ok, _} = OAuth.refresh_tokens(t.refresh_token, ctx.client.id)
    assert %{tokens: 0} = Janitor.run()
  end

  test "a raising run_fun never crashes the janitor process; it logs and reschedules" do
    pid =
      start_supervised!(
        {Janitor,
         [
           enabled: true,
           interval_ms: 60_000,
           initial_delay_ms: 0,
           run_fun: fn -> raise "boom" end,
           name: :janitor_under_test
         ]}
      )

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    ExUnit.CaptureLog.capture_log(fn ->
      send(pid, :run)
      # Synchronous round-trip: guarantees the prior :run message has been
      # handled before we assert liveness (no Process.sleep race).
      :sys.get_state(pid)
    end)

    assert Process.alive?(pid)
  end

  test "handle_info(:run, ...) is a no-op and does not reschedule when disabled" do
    pid =
      start_supervised!(
        {Janitor, [enabled: false, interval_ms: 60_000, name: :disabled_janitor_under_test]}
      )

    send(pid, :run)
    :sys.get_state(pid)

    assert Process.alive?(pid)
    assert {:noreply, %{enabled: false}} = Janitor.handle_info(:run, %{enabled: false})
  end
end
