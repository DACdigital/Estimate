defmodule Estimate.MCP.OAuth.JanitorTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.MCP.OAuth
  alias Estimate.MCP.OAuth.{Client, Code, Janitor, Token}
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

  defp hours_ago(hours),
    do: DateTime.utc_now() |> DateTime.add(-hours, :hour) |> DateTime.truncate(:second)

  defp age_client(client, inserted_at) do
    {1, _} =
      Repo.update_all(from(c in Client, where: c.id == ^client.id),
        set: [inserted_at: inserted_at]
      )

    :ok
  end

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

    assert %{codes: codes, tokens: 1, clients: 0} = Janitor.run()
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

  describe "orphan client pruning" do
    test "a client with no codes and no tokens older than 24h is deleted", ctx do
      age_client(ctx.client, hours_ago(25))

      assert %{clients: 1} = Janitor.run()
      refute Repo.get(Client, ctx.client.id)
    end

    test "a client with no codes and no tokens younger than 24h is kept (registration grace)",
         ctx do
      age_client(ctx.client, hours_ago(23))

      assert %{clients: 0} = Janitor.run()
      assert Repo.get(Client, ctx.client.id)
    end

    test "a client whose only token is revoked but not yet pruned is kept", ctx do
      t = mint(ctx)
      {:ok, _} = OAuth.refresh_tokens(t.refresh_token, ctx.client.id)
      # revoke the rotated replacement too so nothing on this client is live
      Repo.update_all(from(t in Token, where: t.client_id == ^ctx.client.id),
        set: [revoked_at: hours_ago(1)]
      )

      age_client(ctx.client, hours_ago(48))

      assert %{tokens: 0, clients: 0} = Janitor.run()
      assert Repo.get(Client, ctx.client.id)
    end

    test "a client with a live token is kept regardless of age", ctx do
      _live = mint(ctx)
      age_client(ctx.client, hours_ago(24 * 400))

      assert %{tokens: 0, codes: 0, clients: 0} = Janitor.run()
      assert Repo.get(Client, ctx.client.id)
    end

    test "a client with an unexchanged, unexpired authorization code is kept", ctx do
      age_client(ctx.client, hours_ago(48))

      {:ok, _unused_code} =
        OAuth.create_code(%{
          client_id: ctx.client.id,
          user_id: ctx.user.id,
          organization_id: ctx.org.id,
          redirect_uri: @redirect,
          code_challenge: @challenge,
          resource: @resource
        })

      assert %{clients: 0, codes: 0} = Janitor.run()
      assert Repo.get(Client, ctx.client.id)
      assert Repo.aggregate(Code, :count) == 1
    end

    test "a client whose last token and code are pruned in this run is deleted in the same run",
         ctx do
      _t = mint(ctx)

      Repo.update_all(from(t in Token, where: t.client_id == ^ctx.client.id),
        set: [revoked_at: ago(8)]
      )

      Repo.update_all(from(c in Code, where: c.client_id == ^ctx.client.id),
        set: [expires_at: ago(1)]
      )

      age_client(ctx.client, hours_ago(48))

      assert %{tokens: 1, codes: 1, clients: 1} = Janitor.run()
      refute Repo.get(Client, ctx.client.id)
      assert Repo.aggregate(Token, :count) == 0
      assert Repo.aggregate(Code, :count) == 0
    end
  end

  test "a raising run_fun never crashes the janitor process; it logs and reschedules" do
    pid =
      start_supervised!({Janitor,
       [
         enabled: true,
         interval_ms: 60_000,
         # High enough that init/1's own scheduled first run never fires
         # during this test — only the explicit `send/2` below (inside
         # capture_log) triggers run_fun, so the "boom" warning it logs
         # never leaks into test output.
         initial_delay_ms: 60_000,
         run_fun: fn -> raise "boom" end,
         name: :janitor_under_test
       ]})

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
