# Audit Batch 2a — OAuth Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the MCP OAuth server a real scope model (`mcp:read` / `mcp:write`) enforced on write tools, let users see and revoke connected apps, cap refresh-token lifetime, bound dynamic client registration, and prune expired auth rows.

**Architecture:** Scope is requested at `/oauth/authorize`, shown on consent, persisted on codes and tokens, carried into anubis claims by `KeyValidator`, and enforced in `EstimateWeb.MCP.Write` before the org write toggle. API keys always carry both scopes. Grants are token families (`family_id`); a "Connected apps" card on `/account` lists and revokes them. A small GenServer prunes expired rows hourly.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8.3 / LiveView 1.1 / Ecto 3.13 / Postgres 17 / anubis_mcp 1.9.

**Spec:** `docs/superpowers/specs/2026-09-02-audit-batch-2-security-design.md`, section "2a. OAuth hardening".

## Global Constraints

- Additive migrations only (new columns with defaults + backfill). No drops, renames or type changes.
- TDD per task: failing test first, run it, implement, run green, commit. `mix test <file>` runs one file; the `test` alias migrates first.
- Diverge-then-assert tests: put the forbidden state in place, prove rejection, prove the DB is unchanged.
- Exact scope strings: `"mcp:read"`, `"mcp:write"`; `"offline_access"` accepted and ignored. Stored as a space-separated string, canonical order read then write: `"mcp:read"` or `"mcp:read mcp:write"`.
- Exact error copy: write tool without write scope → `"this connection was authorized read-only; reconnect it and grant write access"`. Unknown scope at authorize → OAuth error code `invalid_scope`.
- Existing OAuth flows (`test/estimate/mcp/*`, `test/estimate_web/controllers/oauth_*`, `test/estimate_web/oauth_end_to_end_test.exs`, `test/estimate_web/mcp/**`) must stay green; when a fixture gains a scope argument it defaults to full scope so existing write-tool tests keep passing.
- All OAuth DB work runs inside `Repo.without_rls/1` (existing convention in `Estimate.MCP.OAuth`).
- Commit signing uses 1Password; on a signing error wait 30 s and retry up to 3 times.
- Finish with `mix precommit` green.

---

### Task 1: Scope column on codes and tokens

**Files:**
- Create: `priv/repo/migrations/20260902130000_add_scope_to_oauth.exs`
- Modify: `lib/estimate/mcp/oauth/code.ex`, `lib/estimate/mcp/oauth/token.ex`
- Create: `lib/estimate/mcp/oauth/scopes.ex`
- Test: `test/estimate/mcp/oauth_scopes_test.exs` (create)

**Interfaces:**
- Produces: `Estimate.MCP.OAuth.Scopes.parse(nil | String.t()) :: {:ok, [String.t()]} | {:error, :invalid_scope}`; `Scopes.join([String.t()]) :: String.t()`; `Scopes.write?([String.t()] | String.t()) :: boolean()`; `Scopes.read_only() :: "mcp:read"`; `Scopes.full() :: "mcp:read mcp:write"`; `Scopes.all() :: ["mcp:read", "mcp:write"]`. Schema fields `Code.scope`, `Token.scope` (`:string`, default `"mcp:read"`).

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Estimate.MCP.OAuth.ScopesTest do
  use Estimate.DataCase, async: true

  alias Estimate.MCP.OAuth.Scopes

  test "absent scope defaults to read" do
    assert Scopes.parse(nil) == {:ok, ["mcp:read"]}
    assert Scopes.parse("") == {:ok, ["mcp:read"]}
  end

  test "read+write parses in canonical order and offline_access is ignored" do
    assert Scopes.parse("mcp:write offline_access mcp:read") == {:ok, ["mcp:read", "mcp:write"]}
    assert Scopes.parse("mcp:write") == {:ok, ["mcp:read", "mcp:write"]}
  end

  test "unknown scope is rejected" do
    assert Scopes.parse("mcp:admin") == {:error, :invalid_scope}
    assert Scopes.parse("mcp:read evil") == {:error, :invalid_scope}
  end

  test "to_string / write? / constants" do
    assert Scopes.join(["mcp:read", "mcp:write"]) == "mcp:read mcp:write"
    assert Scopes.write?("mcp:read mcp:write")
    refute Scopes.write?("mcp:read")
    refute Scopes.write?(["mcp:read"])
    assert Scopes.read_only() == "mcp:read"
    assert Scopes.full() == "mcp:read mcp:write"
  end

  test "codes and tokens have a scope column defaulting to mcp:read" do
    for table <- ~w(oauth_codes oauth_tokens) do
      %{rows: [[default, nullable]]} =
        Estimate.Repo.query!(
          "SELECT column_default, is_nullable FROM information_schema.columns WHERE table_name = $1 AND column_name = 'scope'",
          [table]
        )

      assert default =~ "mcp:read"
      assert nullable == "NO"
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/mcp/oauth_scopes_test.exs`
Expected: FAIL — `Scopes` undefined; column query returns no rows (`MatchError`).

- [ ] **Step 3: Migration**

```elixir
defmodule Estimate.Repo.Migrations.AddScopeToOauth do
  use Ecto.Migration

  # Existing grants were consented as read-only; the default backfills them as such.
  def change do
    alter table(:oauth_codes) do
      add :scope, :string, null: false, default: "mcp:read"
    end

    alter table(:oauth_tokens) do
      add :scope, :string, null: false, default: "mcp:read"
    end
  end
end
```

- [ ] **Step 4: Schema fields and Scopes module**

Add `field :scope, :string, default: "mcp:read"` to both `Code` and `Token` schemas (after `resource` / after `last_used_at`).

`lib/estimate/mcp/oauth/scopes.ex`:

```elixir
defmodule Estimate.MCP.OAuth.Scopes do
  @moduledoc """
  The two MCP OAuth scopes. `mcp:write` implies `mcp:read`; `offline_access`
  (advertised for refresh tokens) is accepted and ignored. Stored on codes and
  tokens as a space-separated string in canonical order.
  """

  @read "mcp:read"
  @write "mcp:write"
  @ignored ["offline_access"]

  def all, do: [@read, @write]
  def read_only, do: @read
  def full, do: "#{@read} #{@write}"

  @spec parse(nil | String.t()) :: {:ok, [String.t()]} | {:error, :invalid_scope}
  def parse(nil), do: {:ok, [@read]}
  def parse(""), do: {:ok, [@read]}

  def parse(scope) when is_binary(scope) do
    requested = scope |> String.split(" ", trim: true) |> Enum.reject(&(&1 in @ignored))

    if Enum.all?(requested, &(&1 in all())) do
      {:ok, if(@write in requested, do: [@read, @write], else: [@read])}
    else
      {:error, :invalid_scope}
    end
  end

  def parse(_), do: {:error, :invalid_scope}

  # Named `join`, not `to_string`: a local `to_string/1` conflicts with the
  # auto-imported Kernel.to_string/1.
  @spec join([String.t()]) :: String.t()
  def join(scopes) when is_list(scopes), do: Enum.join(scopes, " ")

  @spec write?([String.t()] | String.t() | nil) :: boolean()
  def write?(scopes) when is_list(scopes), do: @write in scopes
  def write?(scope) when is_binary(scope), do: @write in String.split(scope, " ", trim: true)
  def write?(_), do: false
end
```

- [ ] **Step 5: Run tests, commit**

Run: `mix test test/estimate/mcp/oauth_scopes_test.exs test/estimate/mcp/`
Expected: PASS.

```bash
git add priv/repo/migrations/20260902130000_add_scope_to_oauth.exs lib/estimate/mcp/oauth/code.ex lib/estimate/mcp/oauth/token.ex lib/estimate/mcp/oauth/scopes.ex test/estimate/mcp/oauth_scopes_test.exs
git commit -m "feat(oauth): scope column on codes/tokens and Scopes parser"
```

---

### Task 2: Scope through the context — code, tokens, refresh, verification, claims

**Files:**
- Modify: `lib/estimate/mcp/oauth.ex` (`create_code/1`, `issue_tokens/1`, `rotate/1`, `check_token/2`)
- Modify: `lib/estimate/mcp.ex` (`authorize/2` returns scope)
- Modify: `lib/estimate/mcp/key_validator.ex`, `lib/estimate_web/mcp/scope.ex`
- Modify: `lib/estimate_web/controllers/oauth_token_controller.ex` (`success/1`)
- Modify: `test/support/fixtures/mcp_fixtures.ex` (`mcp_frame/4` with scope, default full)
- Test: `test/estimate/mcp/oauth_flow_test.exs` (append), `test/estimate/mcp/verify_bearer_test.exs` (append), `test/estimate/mcp/key_validator_test.exs` (append)

**Interfaces:**
- Consumes: `Scopes` from Task 1.
- Produces: `OAuth.create_code/1` accepts `:scope` (string, default `Scopes.read_only()`); tokens returned by `exchange_code/2` and `refresh_tokens/2` include `scope: String.t()`; `verify_access_token/1` and `MCP.verify_api_key/1` auth maps include `scope: String.t()` (API keys → `Scopes.full()`); `KeyValidator` claims include `"scope"`; `Scope.claims/1` includes `scopes :: [String.t()]` (absent claim → `["mcp:read"]`, fail closed).

- [ ] **Step 1: Failing tests**

Append to `oauth_flow_test.exs` (uses its `mint_code/1`, `exchange/2` helpers; `mint_code` gets an optional attrs override — add a second clause `defp mint_code(ctx, extra)` merging `extra` into the `create_code` map):

```elixir
  describe "scope" do
    test "defaults to mcp:read and survives exchange and refresh", ctx do
      code = mint_code(ctx)
      assert {:ok, %{scope: "mcp:read", refresh_token: rt}} = exchange(ctx, code)
      assert {:ok, %{scope: "mcp:read"}} = OAuth.refresh_tokens(rt, ctx.client.id)
    end

    test "write scope is persisted on code and token and verified on the access token", ctx do
      code = mint_code(ctx, %{scope: "mcp:read mcp:write"})
      assert {:ok, %{scope: "mcp:read mcp:write", access_token: at, refresh_token: rt}} = exchange(ctx, code)
      assert {:ok, %{scope: "mcp:read mcp:write"}} = OAuth.verify_access_token(at)
      assert {:ok, %{scope: "mcp:read mcp:write", access_token: at2}} = OAuth.refresh_tokens(rt, ctx.client.id)
      assert {:ok, %{scope: "mcp:read mcp:write"}} = OAuth.verify_access_token(at2)
    end
  end
```

Append to `verify_bearer_test.exs` (see its existing setup for how a key and an access token are minted):

```elixir
  test "api keys carry full scope; oauth access tokens carry their granted scope", ctx do
    assert {:ok, %{scope: "mcp:read mcp:write"}} = Estimate.MCP.verify_bearer(ctx.api_key_plaintext)
    assert {:ok, %{scope: "mcp:read"}} = Estimate.MCP.verify_bearer(ctx.access_token)
  end
```

(Adapt the two context keys to the names that file's setup already binds; if it does not bind both, mint them with the same helpers the file uses for its other tests.)

Append to `key_validator_test.exs`:

```elixir
  test "claims include scope", ctx do
    assert {:ok, %{"scope" => "mcp:read mcp:write"}} =
             Estimate.MCP.KeyValidator.validate_token(ctx.api_key_plaintext, %{resource: "urn:x"})
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/mcp/oauth_flow_test.exs test/estimate/mcp/verify_bearer_test.exs test/estimate/mcp/key_validator_test.exs`
Expected: new tests FAIL (`scope` key missing / `KeyError` on `attrs.scope`).

- [ ] **Step 3: Context changes**

`oauth.ex`:
- `create_code/1`: `scope: Map.get(attrs, :scope, Scopes.read_only())` in the `%Code{}` row (alias `Estimate.MCP.OAuth.Scopes`).
- `issue_tokens/1`: `%Token{... scope: code.scope ...}`; return map gains `scope: code.scope`.
- `rotate/1`: inserted `%Token{}` gets `scope: locked.scope`; return map gains `scope: locked.scope`.
- `check_token/2` success: `{:ok, %{user_id: ..., organization_id: ..., role: hit.role, scope: token.scope}}`.

`mcp.ex` `authorize/2`: `%{user_id: key.user_id, organization_id: key.organization_id, role: role, scope: Estimate.MCP.OAuth.Scopes.full()}`.

`key_validator.ex`:
```elixir
      {:ok, %{user_id: user_id, organization_id: org_id, role: role, scope: scope}} ->
        {:ok,
         %{"sub" => user_id, "org_id" => org_id, "role" => role, "scope" => scope, "aud" => config.resource}}
```

`scope.ex` `claims/1`:
```elixir
    %{
      user_id: auth.sub,
      org_id: auth.raw_claims["org_id"],
      role: auth.raw_claims["role"],
      scopes: parse_scopes(auth.raw_claims["scope"])
    }
  ...
  # Fail closed: a claim set without scope is read-only.
  defp parse_scopes(nil), do: ["mcp:read"]
  defp parse_scopes(scope) when is_binary(scope), do: String.split(scope, " ", trim: true)
```

`oauth_token_controller.ex` `success/1`: `scope: tokens.scope` instead of the hard-coded `"mcp:read"`.

`mcp_fixtures.ex`:
```elixir
  @doc "A frame shaped like anubis builds after successful authorization. Defaults to full scope (API-key parity)."
  def mcp_frame(user, organization, role \\ "owner", scope \\ Estimate.MCP.OAuth.Scopes.full()) do
    %Frame{
      context: %Anubis.Server.Context{
        auth: %{
          sub: user.id,
          raw_claims: %{"org_id" => organization.id, "role" => role, "scope" => scope}
        }
      }
    }
  end
```

- [ ] **Step 4: Run tests, commit**

Run: `mix test test/estimate/mcp/ test/estimate_web/mcp/ test/estimate_web/controllers/oauth_token_test.exs test/estimate_web/oauth_end_to_end_test.exs`
Expected: PASS.

```bash
git add lib/estimate/mcp/oauth.ex lib/estimate/mcp.ex lib/estimate/mcp/key_validator.ex lib/estimate_web/mcp/scope.ex lib/estimate_web/controllers/oauth_token_controller.ex test/support/fixtures/mcp_fixtures.ex test/estimate/mcp/
git commit -m "feat(oauth): carry scope through codes, tokens, refresh, bearer verification and claims"
```

---

### Task 3: Scope at authorize + consent; enforce write scope in tools; copy

**Files:**
- Modify: `lib/estimate_web/controllers/oauth_authorize_controller.ex` (`show/2`, `approve/2`, hidden params)
- Modify: `lib/estimate_web/controllers/oauth_authorize_html/consent.html.heex`
- Modify: `lib/estimate_web/controllers/oauth_metadata_controller.ex`
- Modify: `lib/estimate_web/mcp/authz.ex`, `lib/estimate_web/mcp/write.ex`
- Modify: `lib/estimate_web/mcp_server.ex:1-5` (moduledoc), `lib/estimate_web/live/settings_live/mcp.ex:14` (copy)
- Test: `test/estimate_web/controllers/oauth_authorize_test.exs` (append), `test/estimate_web/mcp/authz_test.exs` (append), `test/estimate_web/mcp/tools/write_customers_test.exs` (append), `test/estimate_web/controllers/oauth_metadata_test.exs` (adjust)

**Interfaces:**
- Consumes: `Scopes`, `Scope.claims/1` `:scopes`.
- Produces: `Authz.require_write_scope(claims) :: :ok | {:error, :insufficient_scope}`.

- [ ] **Step 1: Failing tests**

`oauth_authorize_test.exs` (uses `authorize_params/2`, `conn` logged in as owner, `client`, `org`):

```elixir
  test "consent lists read scope only by default", %{conn: conn, client: client} do
    html = conn |> get(~p"/oauth/authorize?#{authorize_params(client)}") |> html_response(200)
    assert html =~ "Read your estimation data"
    refute html =~ "Create and edit customers"
    refute html =~ "read-only"
  end

  test "consent lists write scope when requested and the code carries it", %{conn: conn, client: client, org: org} do
    params = authorize_params(client, %{"scope" => "mcp:read mcp:write"})
    html = conn |> get(~p"/oauth/authorize?#{params}") |> html_response(200)
    assert html =~ "Create and edit customers, projects and estimations as you"
    assert html =~ ~s(name="scope")

    conn = post(conn, ~p"/oauth/authorize", Map.merge(params, %{"decision" => "approve", "organization_id" => org.id}))
    assert redirected_to(conn) =~ "code=est_ac_"

    assert %Estimate.MCP.OAuth.Code{scope: "mcp:read mcp:write"} =
             Estimate.Repo.one!(Estimate.MCP.OAuth.Code)
  end

  test "unknown scope is an invalid_scope error redirect", %{conn: conn, client: client} do
    conn = get(conn, ~p"/oauth/authorize?#{authorize_params(client, %{"scope" => "mcp:admin"})}")
    assert redirected_to(conn) =~ "error=invalid_scope"
    assert redirected_to(conn) =~ "state=xyz"
  end
```

`authz_test.exs`:
```elixir
  describe "require_write_scope" do
    test "write scope passes, read-only fails", %{owner: owner, org: org} do
      full = Scope.claims(mcp_frame(owner, org, "owner"))
      assert Authz.require_write_scope(full) == :ok
      ro = Scope.claims(mcp_frame(owner, org, "owner", "mcp:read"))
      assert Authz.require_write_scope(ro) == {:error, :insufficient_scope}
    end
  end
```

`write_customers_test.exs`:
```elixir
  test "read-only oauth scope cannot write even with the toggle on", %{owner: owner, org: org} do
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(%{key: "ACME", name: "Acme"}, mcp_frame(owner, org, "owner", "mcp:read"))

    assert json_error(resp) =~ "authorized read-only"
    refute Estimate.Repo.get_by(Estimate.CRM.Customer, key: "ACME")
  end
```

`oauth_metadata_test.exs`: change the `scopes_supported` assertions to `["mcp:read", "mcp:write", "offline_access"]` (authorization server) and `["mcp:read", "mcp:write"]` (protected resource).

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/controllers/oauth_authorize_test.exs test/estimate_web/mcp/authz_test.exs test/estimate_web/mcp/tools/write_customers_test.exs test/estimate_web/controllers/oauth_metadata_test.exs`
Expected: FAIL.

- [ ] **Step 3: Authorize controller**

In `show/2` and `approve/2`, add `{:ok, scopes} <- parse_scope(params)` to the `with` after `validate_request/1`, and a new `else` clause:

```elixir
      {:error, :invalid_scope, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "invalid_scope", params["state"])
```

```elixir
  defp parse_scope(params) do
    case Scopes.parse(params["scope"]) do
      {:ok, scopes} -> {:ok, scopes}
      {:error, :invalid_scope} -> {:error, :invalid_scope, params["redirect_uri"]}
    end
  end
```

`show/2` passes `scopes: scopes` to `render(:consent, ...)`. `approve/2` passes `scope: Scopes.join(scopes)` to `OAuth.create_code/1`. Add `"scope"` to the hidden-input `Map.take` list in the template. Alias `Estimate.MCP.OAuth.Scopes`.

Consent template: replace the read-only sentence with

```heex
  <p class="text-sm text-base-content/60 mb-3">
    <span class="font-mono">{@redirect_host}</span> is asking to access your estimation data, acting as you:
  </p>
  <ul class="mb-4 space-y-1.5 text-sm">
    <li class="flex items-center gap-2 text-base-content">
      <.icon name="hero-eye" class="w-4 h-4 text-base-content/50" /> Read your estimation data
    </li>
    <li :if={"mcp:write" in @scopes} class="flex items-center gap-2 text-warning">
      <.icon name="hero-pencil-square" class="w-4 h-4" />
      Create and edit customers, projects and estimations as you
    </li>
  </ul>
```

Metadata controller: `scopes_supported: ["mcp:read", "mcp:write", "offline_access"]` and `["mcp:read", "mcp:write"]`.

- [ ] **Step 4: Enforce in tools**

`authz.ex`:
```elixir
  alias Estimate.MCP.OAuth.Scopes

  def require_write_scope(%{scopes: scopes}) do
    if Scopes.write?(scopes), do: :ok, else: {:error, :insufficient_scope}
  end
```

`write.ex` `execute/3`: `with :ok <- Authz.require_write_scope(claims), :ok <- Authz.require_write_enabled(claims), :ok <- gate_fun.(claims) do`. Add render clause before the binary-message clause:

```elixir
  defp render({:error, :insufficient_scope}),
    do:
      Response.error(
        Response.tool(),
        "this connection was authorized read-only; reconnect it and grant write access"
      )
```

Copy: `mcp_server.ex` moduledoc → "MCP server for estimation data. Auth: per-user org-scoped API keys or OAuth access tokens (Bearer), validated by `Estimate.MCP.KeyValidator`; write tools additionally require the `mcp:write` scope and the org write toggle." `settings_live/mcp.ex:14` → "Expose org data to MCP clients (Claude Code, Claude Desktop, Cursor…). Personal API keys have full access; OAuth connectors get the scopes you approve."

- [ ] **Step 5: Run tests, commit**

Run: `mix test test/estimate_web/controllers/ test/estimate_web/mcp/ test/estimate_web/oauth_end_to_end_test.exs test/estimate_web/live/settings_live/mcp_test.exs`
Expected: PASS.

```bash
git add lib/estimate_web/controllers/oauth_authorize_controller.ex lib/estimate_web/controllers/oauth_authorize_html/consent.html.heex lib/estimate_web/controllers/oauth_metadata_controller.ex lib/estimate_web/mcp/authz.ex lib/estimate_web/mcp/write.ex lib/estimate_web/mcp_server.ex lib/estimate_web/live/settings_live/mcp.ex test/estimate_web/
git commit -m "feat(oauth): request and consent scopes; write tools require mcp:write"
```

---

### Task 4: Grants — list, revoke, revoke on password change

**Files:**
- Modify: `lib/estimate/mcp/oauth.ex` (add `list_grants/1`, `revoke_grant/2`, `revoke_all_for_user/1`; make `revoke_family/1` public)
- Modify: `lib/estimate/accounts.ex` (`update_password_and_delete_tokens/2`)
- Test: `test/estimate/mcp/oauth_grants_test.exs` (create), `test/estimate/accounts_test.exs` (append)

**Interfaces:**
- Produces: `OAuth.list_grants(user_id) :: [%{family_id, client_name, organization_name, scope, granted_at, last_used_at}]` ordered by `granted_at` desc; `OAuth.revoke_grant(user_id, family_id) :: {:ok, non_neg_integer()} | {:error, :not_found}`; `OAuth.revoke_all_for_user(user_id) :: :ok`.

- [ ] **Step 1: Failing tests**

```elixir
defmodule Estimate.MCP.OAuthGrantsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.MCP.OAuth
  alias Estimate.Organizations

  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  @challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @resource "http://localhost:4000/mcp"
  @redirect "https://claude.ai/api/mcp/auth_callback"

  defp grant(user, org, client, scope \\ "mcp:read") do
    {:ok, code} =
      OAuth.create_code(%{client_id: client.id, user_id: user.id, organization_id: org.id,
        redirect_uri: @redirect, code_challenge: @challenge, resource: @resource, scope: scope})

    {:ok, tokens} =
      OAuth.exchange_code(code, %{client_id: client.id, redirect_uri: @redirect,
        code_verifier: @verifier, resource: @resource})

    tokens
  end

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    {:ok, client} = OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => [@redirect]})
    %{user: user, org: org, client: client}
  end

  test "list_grants shows one entry per family with client, org, scope", ctx do
    t1 = grant(ctx.user, ctx.org, ctx.client, "mcp:read mcp:write")
    # rotate once: still one family
    {:ok, _} = OAuth.refresh_tokens(t1.refresh_token, ctx.client.id)

    assert [g] = OAuth.list_grants(ctx.user.id)
    assert g.client_name == "Claude"
    assert g.organization_name == ctx.org.name
    assert g.scope == "mcp:read mcp:write"
    assert %DateTime{} = g.granted_at
  end

  test "revoke_grant kills the family; other users cannot revoke it", ctx do
    t = grant(ctx.user, ctx.org, ctx.client)
    [g] = OAuth.list_grants(ctx.user.id)

    %{user: other} = user_with_organization_fixture()
    assert OAuth.revoke_grant(other.id, g.family_id) == {:error, :not_found}
    assert {:ok, %{}} = OAuth.verify_access_token(t.access_token)

    assert {:ok, 1} = OAuth.revoke_grant(ctx.user.id, g.family_id)
    assert {:error, :invalid_key} = OAuth.verify_access_token(t.access_token)
    assert {:error, :invalid_grant} = OAuth.refresh_tokens(t.refresh_token, ctx.client.id)
    assert OAuth.list_grants(ctx.user.id) == []
  end

  test "revoke_all_for_user revokes every family of that user only", ctx do
    t1 = grant(ctx.user, ctx.org, ctx.client)
    %{user: other, organization: org2} = user_with_organization_fixture()
    {:ok, org2} = Organizations.update_mcp_settings(org2, %{mcp_enabled: true})
    t2 = grant(other, org2, ctx.client)

    assert :ok = OAuth.revoke_all_for_user(ctx.user.id)
    assert {:error, :invalid_key} = OAuth.verify_access_token(t1.access_token)
    assert {:ok, %{}} = OAuth.verify_access_token(t2.access_token)
  end
end
```

`accounts_test.exs` (append; `valid_user_password/0` and `user_fixture/0` exist):
```elixir
  test "changing the password revokes OAuth grants", %{} do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    {:ok, client} = Estimate.MCP.OAuth.register_client(%{"client_name" => "C", "redirect_uris" => ["https://claude.ai/cb"]})
    {:ok, code} = Estimate.MCP.OAuth.create_code(%{client_id: client.id, user_id: user.id, organization_id: org.id,
      redirect_uri: "https://claude.ai/cb", code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", resource: "http://localhost:4000/mcp"})
    {:ok, tokens} = Estimate.MCP.OAuth.exchange_code(code, %{client_id: client.id, redirect_uri: "https://claude.ai/cb",
      code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", resource: "http://localhost:4000/mcp"})

    {:ok, _} = Estimate.Accounts.update_user_password(user, valid_user_password(), %{"password" => "new long password 123", "password_confirmation" => "new long password 123"})
    assert {:error, :invalid_key} = Estimate.MCP.OAuth.verify_access_token(tokens.access_token)
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/mcp/oauth_grants_test.exs test/estimate/accounts_test.exs`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement in `oauth.ex`**

```elixir
  @doc "Active grants (token families) for a user, newest first."
  def list_grants(user_id) do
    Repo.without_rls(fn ->
      from(t in Token,
        join: c in Client, on: c.id == t.client_id,
        join: o in Organization, on: o.id == t.organization_id,
        left_join: code in Code, on: code.id == t.code_id,
        where: t.user_id == ^user_id and is_nil(t.revoked_at) and t.refresh_expires_at > ^now(),
        group_by: [t.family_id, c.name, o.name, t.scope],
        select: %{
          family_id: t.family_id,
          client_name: c.name,
          organization_name: o.name,
          scope: t.scope,
          granted_at: min(coalesce(code.inserted_at, t.inserted_at)),
          last_used_at: max(t.last_used_at)
        },
        order_by: [desc: min(coalesce(code.inserted_at, t.inserted_at))]
      )
      |> Repo.all()
    end)
  end

  @doc "Revokes a family only if it belongs to `user_id`."
  def revoke_grant(user_id, family_id) do
    Repo.without_rls(fn ->
      owned? =
        Repo.exists?(from(t in Token, where: t.family_id == ^family_id and t.user_id == ^user_id))

      if owned? do
        {count, _} =
          Repo.update_all(
            from(t in Token, where: t.family_id == ^family_id and is_nil(t.revoked_at)),
            set: [revoked_at: now()]
          )

        {:ok, count}
      else
        {:error, :not_found}
      end
    end)
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc "Revokes every live token of the user (all orgs). Called on password change."
  def revoke_all_for_user(user_id) do
    Repo.without_rls(fn ->
      Repo.update_all(
        from(t in Token, where: t.user_id == ^user_id and is_nil(t.revoked_at)),
        set: [revoked_at: now()]
      )
    end)

    :ok
  end
```

`accounts.ex` `update_password_and_delete_tokens/2`: in the `{:ok, %{user: user}}` branch call `Estimate.MCP.OAuth.revoke_all_for_user(user.id)` before returning `{:ok, user}`. (It runs after the transaction commits — the same post-commit pattern used elsewhere in the module.)

- [ ] **Step 4: Run tests, commit**

Run: `mix test test/estimate/mcp/ test/estimate/accounts_test.exs`
Expected: PASS.

```bash
git add lib/estimate/mcp/oauth.ex lib/estimate/accounts.ex test/estimate/mcp/oauth_grants_test.exs test/estimate/accounts_test.exs
git commit -m "feat(oauth): list and revoke grants; revoke all on password change"
```

---

### Task 5: Connected apps card on /account

**Files:**
- Modify: `lib/estimate_web/live/user_live/account_settings.ex`
- Test: `test/estimate_web/live/user_live/connected_apps_test.exs` (create)

**Interfaces:**
- Consumes: `OAuth.list_grants/1`, `OAuth.revoke_grant/2`.

- [ ] **Step 1: Failing test**

```elixir
defmodule EstimateWeb.UserLive.ConnectedAppsTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  alias Estimate.MCP.OAuth
  alias Estimate.Organizations

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  defp grant(user, org) do
    {:ok, client} = OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => ["https://claude.ai/cb"]})
    {:ok, code} = OAuth.create_code(%{client_id: client.id, user_id: user.id, organization_id: org.id,
      redirect_uri: "https://claude.ai/cb", code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
      resource: "http://localhost:4000/mcp", scope: "mcp:read mcp:write"})
    {:ok, tokens} = OAuth.exchange_code(code, %{client_id: client.id, redirect_uri: "https://claude.ai/cb",
      code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", resource: "http://localhost:4000/mcp"})
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
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/live/user_live/connected_apps_test.exs`
Expected: FAIL — no "Connected apps" text, unknown events.

- [ ] **Step 3: Implement the card**

In `mount/3` add `|> assign(:grants, OAuth.list_grants(user.id)) |> assign(:revoking_family_id, nil)` (alias `Estimate.MCP.OAuth`). In `render/1` add `<.connected_apps_card grants={@grants} revoking_family_id={@revoking_family_id} />` after the two-factor card.

```elixir
  attr :grants, :list, required: true
  attr :revoking_family_id, :string, default: nil

  defp connected_apps_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden" id="connected-apps">
      <div class="p-6">
        <h2 class="text-xl font-semibold text-base-content">Connected apps</h2>
        <p class="mt-1 text-sm text-base-content/60">
          MCP clients you authorized with OAuth. Revoking signs the app out immediately.
        </p>

        <p :if={@grants == []} class="mt-4 text-sm text-base-content/60">No connected apps.</p>

        <ul :if={@grants != []} class="mt-4 divide-y divide-base-200">
          <li :for={g <- @grants} class="flex items-center gap-4 py-3">
            <div class="min-w-0 flex-1">
              <div class="text-sm font-medium text-base-content truncate">{g.client_name}</div>
              <div class="text-xs text-base-content/60 font-mono truncate">
                {g.organization_name} · {scope_label(g.scope)} · granted {Calendar.strftime(g.granted_at, "%b %d, %Y")}
              </div>
            </div>
            <button
              type="button"
              phx-click="confirm_revoke_grant"
              phx-value-family-id={g.family_id}
              class="text-base-content/40 hover:text-error transition-colors"
              aria-label={"Revoke #{g.client_name}"}
            >
              <.icon name="hero-x-circle" class="w-4 h-4" />
            </button>
          </li>
        </ul>
      </div>

      <.confirm_modal
        :if={@revoking_family_id}
        id="revoke-grant-modal"
        title="Revoke access?"
        message="The app will lose access immediately and must be connected again."
        confirm_event="revoke_grant"
        cancel_event="cancel_revoke_grant"
        confirm_text="Revoke"
      />
    </div>
    """
  end

  defp scope_label(scope) do
    if Estimate.MCP.OAuth.Scopes.write?(scope), do: "Read and write", else: "Read-only"
  end
```

Events:

```elixir
  def handle_event("confirm_revoke_grant", %{"family-id" => id}, socket),
    do: {:noreply, assign(socket, :revoking_family_id, id)}

  def handle_event("cancel_revoke_grant", _params, socket),
    do: {:noreply, assign(socket, :revoking_family_id, nil)}

  def handle_event("revoke_grant", _params, socket) do
    user_id = socket.assigns.current_user.id

    socket =
      case socket.assigns.revoking_family_id do
        nil ->
          socket

        family_id ->
          case OAuth.revoke_grant(user_id, family_id) do
            {:ok, _} -> put_flash(socket, :info, "Access revoked")
            {:error, :not_found} -> put_flash(socket, :error, "Not found")
          end
      end

    {:noreply,
     socket
     |> assign(:revoking_family_id, nil)
     |> assign(:grants, OAuth.list_grants(user_id))}
  end
```

Check `confirm_modal`'s attrs (`core_components.ex:917-925`): `id`, `title`, `message`, `confirm_event`, `cancel_event`, `confirm_text`, `cancel_text`.

- [ ] **Step 4: Run tests, commit**

Run: `mix test test/estimate_web/live/user_live/`
Expected: PASS (including existing `account_security_test.exs`).

```bash
git add lib/estimate_web/live/user_live/account_settings.ex test/estimate_web/live/user_live/connected_apps_test.exs
git commit -m "feat(account): connected apps card with revoke"
```

---

### Task 6: Absolute refresh lifetime and DCR limits

**Files:**
- Modify: `lib/estimate/mcp/oauth.ex` (`refresh_tokens/2`), `lib/estimate/mcp/oauth/client.ex`
- Test: `test/estimate/mcp/oauth_flow_test.exs` (append), `test/estimate/mcp/oauth_clients_test.exs` (append)

- [ ] **Step 1: Failing tests**

`oauth_flow_test.exs`:
```elixir
  describe "absolute lifetime" do
    test "refresh is refused 90 days after the original consent even if the sliding window is open", ctx do
      code = mint_code(ctx)
      {:ok, %{refresh_token: rt}} = exchange(ctx, code)

      # backdate the originating code to 91 days ago
      old = DateTime.utc_now() |> DateTime.add(-91, :day) |> DateTime.truncate(:second)
      Repo.update_all(Estimate.MCP.OAuth.Code, set: [inserted_at: old])

      assert {:error, :invalid_grant} = OAuth.refresh_tokens(rt, ctx.client.id)
    end

    test "refresh still works at 89 days", ctx do
      code = mint_code(ctx)
      {:ok, %{refresh_token: rt}} = exchange(ctx, code)
      old = DateTime.utc_now() |> DateTime.add(-89, :day) |> DateTime.truncate(:second)
      Repo.update_all(Estimate.MCP.OAuth.Code, set: [inserted_at: old])
      assert {:ok, _} = OAuth.refresh_tokens(rt, ctx.client.id)
    end
  end
```

`oauth_clients_test.exs` (see its existing shape):
```elixir
  test "client_name longer than 100 chars is rejected" do
    assert {:error, cs} = OAuth.register_client(%{"client_name" => String.duplicate("x", 101), "redirect_uris" => ["https://claude.ai/cb"]})
    assert %{name: [_]} = errors_on(cs)
  end

  test "more than 5 redirect uris or a uri over 2048 chars is rejected" do
    many = for i <- 1..6, do: "https://claude.ai/cb#{i}"
    assert {:error, cs} = OAuth.register_client(%{"client_name" => "C", "redirect_uris" => many})
    assert %{redirect_uris: [_ | _]} = errors_on(cs)

    long = "https://claude.ai/" <> String.duplicate("a", 2048)
    assert {:error, cs} = OAuth.register_client(%{"client_name" => "C", "redirect_uris" => [long]})
    assert %{redirect_uris: [_ | _]} = errors_on(cs)
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/mcp/oauth_flow_test.exs test/estimate/mcp/oauth_clients_test.exs`
Expected: FAIL (refresh succeeds at 91 days; long names accepted).

- [ ] **Step 3: Implement**

`oauth.ex`: add `@absolute_ttl_seconds 60 * 60 * 24 * 90` and, in `refresh_tokens/2`'s `cond`, before `not org_enabled_and_member?(row)`:

```elixir
        past_absolute_lifetime?(row) ->
          # 90 days after the original consent the family dies regardless of
          # the sliding refresh window; the user must consent again.
          {:error, :invalid_grant}
```

```elixir
  defp past_absolute_lifetime?(%Token{code_id: nil}), do: false

  defp past_absolute_lifetime?(%Token{code_id: code_id}) do
    case Repo.one(from(c in Code, where: c.id == ^code_id, select: c.inserted_at)) do
      nil -> false
      granted_at -> DateTime.diff(now(), granted_at) > @absolute_ttl_seconds
    end
  end
```

(`code_id` is `nilify_all` on code deletion, so a pruned code cannot kill a live family — the Janitor in Task 7 only deletes codes older than 1 hour past expiry, which are all consumed or dead; the sliding window still bounds those families.)

`client.ex` `registration_changeset/2`: after `validate_required`:
```elixir
    |> validate_length(:name, max: 100)
    |> validate_length(:redirect_uris, min: 1, max: 5)
    |> validate_change(:redirect_uris, fn :redirect_uris, uris ->
      if Enum.all?(uris, &(String.length(&1) <= 2048)), do: [], else: [redirect_uris: "URIs must be at most 2048 characters"]
    end)
```
(replace the existing `validate_length(:redirect_uris, min: 1)`; keep the existing `valid_for_registration?` check).

- [ ] **Step 4: Run tests, commit**

Run: `mix test test/estimate/mcp/ test/estimate_web/controllers/oauth_registration_test.exs test/estimate_web/oauth_end_to_end_test.exs`
Expected: PASS.

```bash
git add lib/estimate/mcp/oauth.ex lib/estimate/mcp/oauth/client.ex test/estimate/mcp/
git commit -m "feat(oauth): 90-day absolute refresh lifetime; bound client registration"
```

---

### Task 7: Janitor for expired codes and tokens

**Files:**
- Create: `lib/estimate/mcp/oauth/janitor.ex`
- Modify: `lib/estimate/application.ex`, `config/config.exs`, `config/test.exs`
- Test: `test/estimate/mcp/oauth_janitor_test.exs` (create)

**Interfaces:**
- Produces: `Estimate.MCP.OAuth.Janitor.run() :: %{codes: non_neg_integer(), tokens: non_neg_integer()}`; GenServer `start_link(opts)` with `interval_ms` (default 1 h) and `enabled` (config, false in test).

- [ ] **Step 1: Failing test**

```elixir
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
    {:ok, client} = OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => [@redirect]})
    %{user: user, org: org, client: client}
  end

  defp mint(ctx) do
    {:ok, code} = OAuth.create_code(%{client_id: ctx.client.id, user_id: ctx.user.id, organization_id: ctx.org.id,
      redirect_uri: @redirect, code_challenge: @challenge, resource: @resource})
    {:ok, tokens} = OAuth.exchange_code(code, %{client_id: ctx.client.id, redirect_uri: @redirect,
      code_verifier: @verifier, resource: @resource})
    tokens
  end

  defp ago(days), do: DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

  test "deletes long-expired codes and long-dead tokens, keeps live ones", ctx do
    live = mint(ctx)
    dead = mint(ctx)
    {:ok, _} = OAuth.refresh_tokens(dead.refresh_token, ctx.client.id) # dead.refresh now revoked
    # age the revoked row and its code
    Repo.update_all(from(t in Token, where: not is_nil(t.revoked_at)), set: [revoked_at: ago(8)])
    Repo.update_all(from(c in Code, where: not is_nil(c.used_at)), set: [expires_at: ago(1)])

    before_tokens = Repo.aggregate(Token, :count)
    assert %{codes: codes, tokens: 1} = Janitor.run()
    assert codes == 2
    assert Repo.aggregate(Token, :count) == before_tokens - 1
    assert {:ok, %{}} = OAuth.verify_access_token(live.access_token)
  end

  test "a token revoked less than 7 days ago is kept", ctx do
    t = mint(ctx)
    {:ok, _} = OAuth.refresh_tokens(t.refresh_token, ctx.client.id)
    assert %{tokens: 0} = Janitor.run()
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/mcp/oauth_janitor_test.exs`
Expected: FAIL — `Janitor` undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule Estimate.MCP.OAuth.Janitor do
  @moduledoc """
  Hourly cleanup of OAuth rows that can no longer be used: authorization
  codes more than an hour past expiry, and tokens revoked or refresh-expired
  more than seven days ago. Runs at boot and then every `interval_ms`.
  Disabled in test (config `enabled: false`); `run/0` is callable directly.
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias Estimate.MCP.OAuth.{Code, Token}
  alias Estimate.Repo

  @default_interval :timer.hours(1)
  @code_grace_seconds 3600
  @token_grace_seconds 7 * 24 * 3600

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    config = Application.get_env(:estimate, __MODULE__, [])
    enabled = Keyword.get(opts, :enabled, Keyword.get(config, :enabled, true))
    interval = Keyword.get(opts, :interval_ms, Keyword.get(config, :interval_ms, @default_interval))

    if enabled, do: send(self(), :run)
    {:ok, %{interval: interval, enabled: enabled}}
  end

  @impl true
  def handle_info(:run, state) do
    counts = run()
    Logger.info("oauth janitor: pruned #{counts.codes} codes, #{counts.tokens} tokens")
    Process.send_after(self(), :run, state.interval)
    {:noreply, state}
  end

  @spec run() :: %{codes: non_neg_integer(), tokens: non_neg_integer()}
  def run do
    Repo.without_rls(fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      code_cutoff = DateTime.add(now, -@code_grace_seconds)
      token_cutoff = DateTime.add(now, -@token_grace_seconds)

      {tokens, _} =
        Repo.delete_all(
          from(t in Token,
            where: t.revoked_at < ^token_cutoff or t.refresh_expires_at < ^token_cutoff
          )
        )

      {codes, _} = Repo.delete_all(from(c in Code, where: c.expires_at < ^code_cutoff))

      %{codes: codes, tokens: tokens}
    end)
  end
end
```

Delete tokens before codes so `code_id` nilification never races the token delete.

`application.ex`: add `Estimate.MCP.OAuth.Janitor` after `Estimate.RateLimit`. `config/config.exs`: `config :estimate, Estimate.MCP.OAuth.Janitor, enabled: true`. `config/test.exs`: `config :estimate, Estimate.MCP.OAuth.Janitor, enabled: false`.

- [ ] **Step 4: Run tests, commit**

Run: `mix test test/estimate/mcp/oauth_janitor_test.exs && mix compile --warnings-as-errors`
Expected: PASS.

```bash
git add lib/estimate/mcp/oauth/janitor.ex lib/estimate/application.ex config/config.exs config/test.exs test/estimate/mcp/oauth_janitor_test.exs
git commit -m "feat(oauth): hourly janitor prunes expired codes and dead tokens"
```

---

### Task 8: Full verification

- [ ] **Step 1:** `mix precommit` — compile with no warnings, unused-deps clean, format clean, full suite green.
- [ ] **Step 2:** Confirm these files exist and pass: `oauth_scopes_test.exs`, `oauth_grants_test.exs`, `oauth_janitor_test.exs`, `connected_apps_test.exs`, the scope additions in `oauth_flow_test.exs`, `oauth_authorize_test.exs`, `write_customers_test.exs`, `authz_test.exs`.
- [ ] **Step 3:** Commit any formatter output: `git add -A && git commit -m "chore: format" || true`.
