# MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose org data read-only at `/mcp` (Streamable HTTP MCP server) with per-user, per-org API keys that inherit the user's RLS privileges, plus an org-admin enable toggle and a `/settings/mcp` page.

**Architecture:** `anubis_mcp ~> 1.8` provides the MCP protocol (JSON-RPC, sessions, Streamable HTTP plug). Our code adds: an `mcp_api_keys` table (sha256-hash-only storage), a custom anubis authorization validator that maps bearer keys → `(user_id, org_id, role)` claims, a `with_scope` helper that sets the app's ambient RLS context per tool execution, 11 read-only tool components delegating to existing contexts, and one settings LiveView.

**Tech Stack:** Elixir/Phoenix 1.8.3, LiveView 1.1, Ecto + Postgres RLS, anubis_mcp 1.8 (LGPL-3.0 — accepted in spec), Jason.

**Spec:** `docs/superpowers/specs/2026-07-16-mcp-server-design.md`

## Global Constraints

- Read-only tools only. No write tools.
- 1 key per `(user_id, organization_id)`; regenerate = delete old + insert new; no expiry.
- Key format: `"est_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)`. DB stores only `:crypto.hash(:sha256, plaintext)` + first 12 chars as `key_prefix`. Plaintext shown exactly once.
- All schemas `use Estimate.Schema` (binary_id PKs). Timestamps `type: :utc_datetime`.
- Context functions take explicit `org_id` args AND wrap DB work in `Repo.ensure_org_context/1` — both, always (existing convention).
- RLS test seeding: insert fixtures BEFORE any role switch; fixtures run as postgres and bypass RLS.
- Characterization/no-tautology rule: when testing that a handler changes state, first diverge the state from its default, then assert the change.
- Serializer outputs must contain only JSON-native values: `Decimal` → `Decimal.to_string/1`, `DateTime` → `DateTime.to_iso8601/1`. Never pass structs to `Response.json/2`.
- Commit messages: extremely concise, conventional prefixes (`feat:`, `test:`, `fix:`).
- Run `mix format` before every commit.
- Anubis facts (verified against v1.8 source/docs, do not re-derive):
  - Validator behaviour: `Anubis.Server.Authorization.Validator`, callback `validate_token(token, config) :: {:ok, raw_claims_map} | {:error, reason}`. Raw claims use string keys.
  - The auth layer normalizes claims to `%{sub:, aud:, scope:, scopes:, exp:, iat:, client_id:, raw_claims: raw}` and then ALWAYS runs audience validation: the claims MUST contain `"aud"` equal to the configured `resource`, else 401. Our validator therefore sets `"aud" => config.resource`.
  - `authorization:` config REQUIRES `authorization_servers` (list), `resource` (string), `validator` ({module, keyword}). We use inert URN values — no OAuth server exists; metadata endpoint is unused by header-auth clients.
  - Tools access claims via `Anubis.Server.Frame.authorization(frame)` → the normalized map.
  - Tool responses: `{:reply, Response.json(Response.tool(), data), frame}`; domain failures: `{:reply, Response.error(Response.tool(), "msg"), frame}` (sets `isError`).
  - Component tool name = module basename snake-cased (`ListCustomers` → `"list_customers"`).

## File Structure

| File | Responsibility |
|---|---|
| `priv/repo/migrations/<ts>_add_mcp_enabled_to_organizations.exs` | org toggle column |
| `priv/repo/migrations/<ts>_create_mcp_api_keys.exs` | keys table + RLS policy |
| `lib/estimate/accounts/organization.ex` (modify) | `mcp_enabled` field + `mcp_settings_changeset/2` |
| `lib/estimate/organizations.ex` (modify) | `update_mcp_settings/2` |
| `lib/estimate/mcp/api_key.ex` | `Estimate.MCP.APIKey` schema |
| `lib/estimate/mcp.ex` | `Estimate.MCP` context: generate/get/revoke/verify |
| `lib/estimate/mcp/key_validator.ex` | anubis validator behaviour impl |
| `lib/estimate_web/mcp_server.ex` | `EstimateWeb.MCPServer` (anubis server, component registry) |
| `lib/estimate_web/mcp/scope.ex` | claims extraction + RLS bridge (`with_scope/2`, `fetch/2`) |
| `lib/estimate_web/mcp/serializers.ex` | struct → JSON-native maps |
| `lib/estimate_web/mcp/tools/*.ex` | 11 tool components (one module each) |
| `lib/estimate_web/live/settings_live/mcp.ex` | settings page LV |
| `lib/estimate_web/router.ex` (modify) | `/mcp` forward + `/settings/mcp` route |
| `lib/estimate/application.ex` (modify) | server child |
| `lib/estimate_web/components/layouts/app.html.heex` (modify) | sidebar link |
| `test/support/fixtures/mcp_fixtures.ex` | frame + key fixtures |
| `test/estimate/organizations_mcp_settings_test.exs` | toggle tests |
| `test/estimate/mcp_test.exs` | context tests |
| `test/estimate/mcp/key_validator_test.exs` | validator tests |
| `test/estimate_web/mcp_server_auth_test.exs` | HTTP auth smoke |
| `test/estimate_web/mcp/tools/*_test.exs` | per-tool unit tests |
| `test/estimate_web/mcp_server_integration_test.exs` | end-to-end + cross-org |
| `test/estimate_web/live/settings_live/mcp_test.exs` | LV tests |

---

### Task 1: Dependency, migrations, org toggle

**Files:**
- Modify: `mix.exs` (deps)
- Create: `priv/repo/migrations/<ts>_add_mcp_enabled_to_organizations.exs`
- Create: `priv/repo/migrations/<ts>_create_mcp_api_keys.exs`
- Modify: `lib/estimate/accounts/organization.ex`
- Modify: `lib/estimate/organizations.ex`
- Test: `test/estimate/organizations_mcp_settings_test.exs`

**Interfaces:**
- Consumes: existing `Estimate.Organizations.update_ai_settings/2` shape (organizations.ex:56), RLS SQL functions `current_org_id()`, `current_user_id()` (already in DB).
- Produces: `organizations.mcp_enabled :boolean` (default false); table `mcp_api_keys(id, key_hash :binary, key_prefix :string, last_used_at, user_id, organization_id, timestamps)` with unique indexes on `key_hash` and `(user_id, organization_id)`; `Organization.mcp_settings_changeset/2`; `Organizations.update_mcp_settings/2 :: {:ok, %Organization{}} | {:error, changeset}`.

- [ ] **Step 1: Add dependency**

In `mix.exs` deps list, after `{:eqrcode, "~> 0.2"}` add:

```elixir
      {:anubis_mcp, "~> 1.8"}
```

Run: `mix deps.get`
Expected: resolves anubis_mcp 1.8.x, no conflicts.

- [ ] **Step 2: Write failing test**

Create `test/estimate/organizations_mcp_settings_test.exs`:

```elixir
defmodule Estimate.OrganizationsMcpSettingsTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures

  alias Estimate.Organizations

  describe "update_mcp_settings/2" do
    test "enables MCP (default is disabled)" do
      %{organization: org} = user_with_organization_fixture()

      refute org.mcp_enabled

      assert {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
      assert org.mcp_enabled
      assert Repo.reload!(org).mcp_enabled
    end

    test "disables MCP after enabling (divergence first — default is already false)" do
      %{organization: org} = user_with_organization_fixture()
      {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})

      assert {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})
      refute Repo.reload!(org).mcp_enabled
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/estimate/organizations_mcp_settings_test.exs`
Expected: FAIL — `mcp_enabled` key error / undefined `update_mcp_settings/2`.

- [ ] **Step 4: Migrations**

Generate: `mix ecto.gen.migration add_mcp_enabled_to_organizations` and fill:

```elixir
defmodule Estimate.Repo.Migrations.AddMcpEnabledToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :mcp_enabled, :boolean, default: false, null: false
    end
  end
end
```

Generate: `mix ecto.gen.migration create_mcp_api_keys` and fill (up/down because of RLS DDL; `estimate_app` grants come from existing default privileges — the `estimation_templates` migration needed no explicit GRANT either):

```elixir
defmodule Estimate.Repo.Migrations.CreateMcpApiKeys do
  use Ecto.Migration

  def up do
    create table(:mcp_api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key_hash, :binary, null: false
      add :key_prefix, :string, null: false
      add :last_used_at, :utc_datetime

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcp_api_keys, [:key_hash])
    create unique_index(:mcp_api_keys, [:user_id, :organization_id])
    create index(:mcp_api_keys, [:organization_id])

    execute "ALTER TABLE mcp_api_keys ENABLE ROW LEVEL SECURITY"

    # Users manage only their own key within the current org context.
    # Bearer-key verification bypasses RLS via Repo.without_rls (pre-context by definition).
    execute """
    CREATE POLICY own_key_isolation ON mcp_api_keys FOR ALL
      USING (organization_id = current_org_id() AND user_id = current_user_id())
      WITH CHECK (organization_id = current_org_id() AND user_id = current_user_id())
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS own_key_isolation ON mcp_api_keys"
    execute "ALTER TABLE mcp_api_keys DISABLE ROW LEVEL SECURITY"
    drop table(:mcp_api_keys)
  end
end
```

Run: `mix ecto.migrate && MIX_ENV=test mix ecto.migrate`
Expected: both migrations run clean in dev and test.

- [ ] **Step 5: Schema + context function**

In `lib/estimate/accounts/organization.ex`, in the `schema` block next to `enforce_2fa`, add:

```elixir
    field :mcp_enabled, :boolean, default: false
```

Below `security_settings_changeset` (or after `smtp_settings_changeset`), add:

```elixir
  @doc "Changeset for the MCP server settings (admin-managed)."
  def mcp_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:mcp_enabled])
    |> validate_required([:mcp_enabled])
  end
```

In `lib/estimate/organizations.ex`, after `update_ai_settings/2` (line ~60), add:

```elixir
  ## MCP Settings

  def update_mcp_settings(%Organization{} = org, attrs) do
    org
    |> Organization.mcp_settings_changeset(attrs)
    |> Repo.update()
  end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/estimate/organizations_mcp_settings_test.exs`
Expected: 2 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
mix format
git add -A
git commit -m "feat: mcp_enabled org toggle + mcp_api_keys table w/ RLS policy + anubis_mcp dep"
```

---

### Task 2: `Estimate.MCP` context — key lifecycle + verification

**Files:**
- Create: `lib/estimate/mcp/api_key.ex`
- Create: `lib/estimate/mcp.ex`
- Create: `test/support/fixtures/mcp_fixtures.ex`
- Test: `test/estimate/mcp_test.exs`

**Interfaces:**
- Consumes: `Estimate.Repo.ensure_org_context/1`, `Repo.without_rls/1`, `Estimate.Accounts.{Membership, Organization}`, Task 1 table.
- Produces:
  - `Estimate.MCP.generate_api_key(user_id, org_id) :: {:ok, {plaintext :: String.t(), %APIKey{}}} | {:error, changeset}`
  - `Estimate.MCP.get_api_key(user_id, org_id) :: %APIKey{} | nil`
  - `Estimate.MCP.revoke_api_key(user_id, org_id) :: non_neg_integer` (deleted count)
  - `Estimate.MCP.verify_api_key(plaintext) :: {:ok, %{user_id: binary, organization_id: binary, role: String.t()}} | {:error, :invalid_key | :not_a_member | :mcp_disabled}`
  - `Estimate.MCPFixtures.mcp_api_key_fixture(user, organization) :: {plaintext, %APIKey{}}` (enables MCP on the org first)

- [ ] **Step 1: Write failing tests**

Create `test/estimate/mcp_test.exs`:

```elixir
defmodule Estimate.MCPTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures

  alias Estimate.MCP
  alias Estimate.MCP.APIKey
  alias Estimate.Organizations

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    %{user: user, org: org}
  end

  describe "generate_api_key/2" do
    test "returns plaintext once, stores only hash + prefix", %{user: user, org: org} do
      assert {:ok, {plaintext, %APIKey{} = key}} = MCP.generate_api_key(user.id, org.id)

      assert String.starts_with?(plaintext, "est_")
      assert key.key_prefix == String.slice(plaintext, 0, 12)
      assert key.key_hash == :crypto.hash(:sha256, plaintext)
      refute Map.has_key?(Map.from_struct(key), :plaintext)
      # plaintext never persisted anywhere
      assert Repo.reload!(key).key_hash == :crypto.hash(:sha256, plaintext)
    end

    test "regenerate replaces the old key and invalidates it", %{user: user, org: org} do
      {:ok, {old_plaintext, old_key}} = MCP.generate_api_key(user.id, org.id)
      {:ok, {new_plaintext, new_key}} = MCP.generate_api_key(user.id, org.id)

      assert old_key.id != new_key.id
      assert Repo.get(APIKey, old_key.id) == nil
      assert {:error, :invalid_key} = MCP.verify_api_key(old_plaintext)
      assert {:ok, _} = MCP.verify_api_key(new_plaintext)
    end
  end

  describe "get_api_key/2 and revoke_api_key/2" do
    test "get returns the key, revoke deletes it", %{user: user, org: org} do
      {:ok, {plaintext, key}} = MCP.generate_api_key(user.id, org.id)

      assert %APIKey{id: id} = MCP.get_api_key(user.id, org.id)
      assert id == key.id

      assert 1 = MCP.revoke_api_key(user.id, org.id)
      assert MCP.get_api_key(user.id, org.id) == nil
      assert {:error, :invalid_key} = MCP.verify_api_key(plaintext)
    end
  end

  describe "verify_api_key/1" do
    test "valid key returns user, org and membership role", %{user: user, org: org} do
      {:ok, {plaintext, _}} = MCP.generate_api_key(user.id, org.id)

      assert {:ok, %{user_id: user_id, organization_id: org_id, role: "owner"}} =
               MCP.verify_api_key(plaintext)

      assert user_id == user.id
      assert org_id == org.id
    end

    test "garbage and wrong-prefix tokens are invalid" do
      assert {:error, :invalid_key} = MCP.verify_api_key("est_" <> "notarealkey123")
      assert {:error, :invalid_key} = MCP.verify_api_key("sk-or-something")
      assert {:error, :invalid_key} = MCP.verify_api_key("")
    end

    test "org toggle off kills the key", %{user: user, org: org} do
      {:ok, {plaintext, _}} = MCP.generate_api_key(user.id, org.id)
      {:ok, _} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})

      assert {:error, :mcp_disabled} = MCP.verify_api_key(plaintext)
    end

    test "membership removal kills the key", %{user: user, org: org} do
      {:ok, {plaintext, _}} = MCP.generate_api_key(user.id, org.id)

      Repo.get_by!(Estimate.Accounts.Membership, user_id: user.id, organization_id: org.id)
      |> Repo.delete!()

      assert {:error, :not_a_member} = MCP.verify_api_key(plaintext)
    end

    test "touches last_used_at at most once per 5 minutes", %{user: user, org: org} do
      {:ok, {plaintext, key}} = MCP.generate_api_key(user.id, org.id)
      assert key.last_used_at == nil

      {:ok, _} = MCP.verify_api_key(plaintext)
      first = Repo.reload!(key).last_used_at
      assert first != nil

      {:ok, _} = MCP.verify_api_key(plaintext)
      assert Repo.reload!(key).last_used_at == first
    end
  end

  describe "RLS policy on mcp_api_keys" do
    test "another user in the same org cannot read my key", %{user: user, org: org} do
      other = user_fixture()
      membership_fixture(other, org, "member")
      {:ok, _} = MCP.generate_api_key(user.id, org.id)

      # Switch to app role with the OTHER user's context — policy must hide the row.
      setup_rls(org.id, other.id)
      assert MCP.get_api_key(user.id, org.id) == nil
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/estimate/mcp_test.exs`
Expected: FAIL — `Estimate.MCP` undefined.

- [ ] **Step 3: Implement schema**

Create `lib/estimate/mcp/api_key.ex`:

```elixir
defmodule Estimate.MCP.APIKey do
  use Estimate.Schema

  import Ecto.Changeset

  schema "mcp_api_keys" do
    field :key_hash, :binary, redact: true
    field :key_prefix, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, Estimate.Accounts.User
    belongs_to :organization, Estimate.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:key_hash, :key_prefix, :user_id, :organization_id])
    |> validate_required([:key_hash, :key_prefix, :user_id, :organization_id])
    |> unique_constraint([:user_id, :organization_id])
    |> unique_constraint(:key_hash)
  end
end
```

(If `Estimate.Schema` sets timestamps itself, drop the explicit `timestamps` line to match sibling schemas — copy whatever `lib/estimate/crm/customer.ex` does.)

- [ ] **Step 4: Implement context**

Create `lib/estimate/mcp.ex`:

```elixir
defmodule Estimate.MCP do
  @moduledoc """
  Per-membership MCP API keys.

  Management functions run under the ambient RLS context (own-key policy).
  `verify_api_key/1` runs via `Repo.without_rls/1` — verification precedes
  any org context by definition, same escape hatch as search reindexing.
  """

  import Ecto.Query

  alias Estimate.Accounts.{Membership, Organization}
  alias Estimate.MCP.APIKey
  alias Estimate.Repo

  @prefix "est_"
  @rand_size 32
  @last_used_resolution_seconds 300

  def generate_api_key(user_id, org_id) do
    plaintext = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(@rand_size), padding: false)

    attrs = %{
      key_hash: :crypto.hash(:sha256, plaintext),
      key_prefix: String.slice(plaintext, 0, 12),
      user_id: user_id,
      organization_id: org_id
    }

    Repo.ensure_org_context(fn ->
      Repo.transaction(fn ->
        Repo.delete_all(own_key_query(user_id, org_id))

        case %APIKey{} |> APIKey.changeset(attrs) |> Repo.insert() do
          {:ok, api_key} -> {plaintext, api_key}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  def get_api_key(user_id, org_id) do
    Repo.ensure_org_context(fn ->
      Repo.get_by(APIKey, user_id: user_id, organization_id: org_id)
    end)
  end

  def revoke_api_key(user_id, org_id) do
    Repo.ensure_org_context(fn ->
      {count, _} = Repo.delete_all(own_key_query(user_id, org_id))
      count
    end)
  end

  def verify_api_key(@prefix <> _rest = plaintext) do
    hash = :crypto.hash(:sha256, plaintext)

    Repo.without_rls(fn ->
      query =
        from k in APIKey,
          join: o in Organization,
          on: o.id == k.organization_id,
          left_join: m in Membership,
          on: m.user_id == k.user_id and m.organization_id == k.organization_id,
          where: k.key_hash == ^hash,
          select: %{key: k, mcp_enabled: o.mcp_enabled, role: m.role}

      case Repo.one(query) do
        nil -> {:error, :invalid_key}
        %{role: nil} -> {:error, :not_a_member}
        %{mcp_enabled: false} -> {:error, :mcp_disabled}
        %{key: key, role: role} -> {:ok, authorize(key, role)}
      end
    end)
  end

  def verify_api_key(_), do: {:error, :invalid_key}

  defp authorize(%APIKey{} = key, role) do
    maybe_touch_last_used(key)
    %{user_id: key.user_id, organization_id: key.organization_id, role: role}
  end

  defp maybe_touch_last_used(%APIKey{} = key) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    stale? =
      is_nil(key.last_used_at) or
        DateTime.diff(now, key.last_used_at) >= @last_used_resolution_seconds

    if stale? do
      from(k in APIKey, where: k.id == ^key.id)
      |> Repo.update_all(set: [last_used_at: now])
    end

    :ok
  end

  defp own_key_query(user_id, org_id) do
    from k in APIKey, where: k.user_id == ^user_id and k.organization_id == ^org_id
  end
end
```

- [ ] **Step 5: Fixtures helper**

Create `test/support/fixtures/mcp_fixtures.ex`:

```elixir
defmodule Estimate.MCPFixtures do
  @moduledoc "Fixtures for MCP API keys and anubis frames."

  alias Anubis.Server.Frame

  @doc "Enables MCP on the org and generates a key. Returns {plaintext, %APIKey{}}."
  def mcp_api_key_fixture(user, organization) do
    {:ok, _} = Estimate.Organizations.update_mcp_settings(organization, %{mcp_enabled: true})
    {:ok, {plaintext, key}} = Estimate.MCP.generate_api_key(user.id, organization.id)
    {plaintext, key}
  end

  @doc "A frame shaped like anubis builds after successful authorization."
  def mcp_frame(user, organization, role \\ "owner") do
    %Frame{
      context: %Anubis.Server.Context{
        auth: %{
          sub: user.id,
          raw_claims: %{"org_id" => organization.id, "role" => role}
        }
      }
    }
  end
end
```

(If `%Anubis.Server.Context{}` has no `:auth` key, check `deps/anubis_mcp/lib/anubis/server/context.ex` for the field that `StreamableHTTP.Plug.build_request_context/2` fills with auth claims and use that name — in 1.8 it is `auth`.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/estimate/mcp_test.exs`
Expected: 8 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
mix format
git add -A
git commit -m "feat: Estimate.MCP context — key generate/revoke/verify, hash-only storage, RLS-tested"
```

---

### Task 3: Validator + server skeleton + supervision + router + auth smoke test

**Files:**
- Create: `lib/estimate/mcp/key_validator.ex`
- Create: `lib/estimate_web/mcp_server.ex`
- Modify: `lib/estimate/application.ex`
- Modify: `lib/estimate_web/router.ex`
- Test: `test/estimate/mcp/key_validator_test.exs`
- Test: `test/estimate_web/mcp_server_auth_test.exs`

**Interfaces:**
- Consumes: `Estimate.MCP.verify_api_key/1` (Task 2).
- Produces: `Estimate.MCP.KeyValidator.validate_token/2` returning `{:ok, %{"sub" => user_id, "org_id" => org_id, "role" => role, "aud" => config.resource}}`; `EstimateWeb.MCPServer` (anubis server, `capabilities: [:tools]`, resource URN `"urn:estimate:mcp"`); HTTP endpoint at `POST /mcp`.

- [ ] **Step 1: Write failing validator tests**

Create `test/estimate/mcp/key_validator_test.exs`:

```elixir
defmodule Estimate.MCP.KeyValidatorTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.MCPFixtures

  alias Estimate.MCP.KeyValidator

  @config %{resource: "urn:estimate:mcp"}

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {plaintext, _key} = mcp_api_key_fixture(user, org)
    %{user: user, org: org, key: plaintext}
  end

  test "valid key → string-keyed claims incl. aud from config", %{user: user, org: org, key: key} do
    assert {:ok, claims} = KeyValidator.validate_token(key, @config)

    assert claims["sub"] == user.id
    assert claims["org_id"] == org.id
    assert claims["role"] == "owner"
    assert claims["aud"] == "urn:estimate:mcp"
  end

  test "invalid key → error" do
    assert {:error, :invalid_key} = KeyValidator.validate_token("est_bogus", @config)
  end

  test "disabled org → error", %{org: org, key: key} do
    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})
    assert {:error, :mcp_disabled} = KeyValidator.validate_token(key, @config)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/mcp/key_validator_test.exs`
Expected: FAIL — `KeyValidator` undefined.

- [ ] **Step 3: Implement validator**

Create `lib/estimate/mcp/key_validator.ex`:

```elixir
defmodule Estimate.MCP.KeyValidator do
  @moduledoc """
  Anubis authorization validator backed by `mcp_api_keys`.

  Sets `aud` to the configured resource because the anubis auth layer
  audience-validates every claims map; we mint the claims ourselves, so
  the audience check is satisfied by construction.
  """

  @behaviour Anubis.Server.Authorization.Validator

  @impl true
  def validate_token(token, config) do
    case Estimate.MCP.verify_api_key(token) do
      {:ok, %{user_id: user_id, organization_id: org_id, role: role}} ->
        {:ok, %{"sub" => user_id, "org_id" => org_id, "role" => role, "aud" => config.resource}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

- [ ] **Step 4: Run validator tests — pass**

Run: `mix test test/estimate/mcp/key_validator_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Server module, supervision, router**

Create `lib/estimate_web/mcp_server.ex`:

```elixir
defmodule EstimateWeb.MCPServer do
  @moduledoc """
  Read-only MCP server. Auth: per-user org-scoped API keys (Bearer),
  validated by `Estimate.MCP.KeyValidator`. Every tool runs inside the
  caller's RLS context via `EstimateWeb.MCP.Scope.with_scope/2`.
  """

  use Anubis.Server,
    name: "estimate",
    version: "1.0.0",
    capabilities: [:tools],
    authorization: [
      # No OAuth AS exists; inert values satisfy anubis' required config.
      # Header-auth clients (Claude Code/Desktop, Cursor) never read the
      # RFC 9728 metadata these feed.
      authorization_servers: ["urn:estimate:none"],
      resource: "urn:estimate:mcp",
      validator: {Estimate.MCP.KeyValidator, []}
    ]

  # Tool components are registered in Tasks 4-7:
  # component EstimateWeb.MCP.Tools.ListCustomers
end
```

In `lib/estimate/application.ex`, add to `children` after `EstimateWeb.Endpoint`:

```elixir
      {EstimateWeb.MCPServer, transport: :streamable_http}
```

In `lib/estimate_web/router.ex`, directly after the health-check scope (after line 26), add:

```elixir
  # MCP server (Streamable HTTP). Auth handled inside the plug via
  # bearer API keys — no session, no CSRF.
  forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: EstimateWeb.MCPServer
```

Run: `mix compile --warnings-as-errors`
Expected: clean compile.

- [ ] **Step 6: Write HTTP auth smoke test**

Create `test/estimate_web/mcp_server_auth_test.exs`:

```elixir
defmodule EstimateWeb.MCPServerAuthTest do
  use Estimate.DataCase, async: false

  import Plug.Conn
  import Plug.Test
  import Estimate.AccountsFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Transport.StreamableHTTP

  @plug_opts StreamableHTTP.Plug.init(server: EstimateWeb.MCPServer)

  setup do
    start_supervised!({EstimateWeb.MCPServer, transport: {:streamable_http, start: true}})

    %{user: user, organization: org} = user_with_organization_fixture()
    {plaintext, _} = mcp_api_key_fixture(user, org)
    %{user: user, org: org, key: plaintext}
  end

  defp post_mcp(body, headers) do
    conn =
      conn(:post, "/", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    headers
    |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> StreamableHTTP.Plug.call(@plug_opts)
  end

  defp init_body do
    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-06-18",
        "clientInfo" => %{"name" => "test", "version" => "1.0.0"},
        "capabilities" => %{}
      }
    }
  end

  test "initialize without key → 401" do
    assert post_mcp(init_body(), []).status == 401
  end

  test "initialize with bogus key → 401" do
    assert post_mcp(init_body(), [{"authorization", "Bearer est_bogus"}]).status == 401
  end

  test "initialize with valid key → 200 + session id", %{key: key} do
    conn = post_mcp(init_body(), [{"authorization", "Bearer " <> key}])
    assert conn.status == 200
    assert [_session_id] = get_resp_header(conn, "mcp-session-id")
  end

  test "org toggle off → 401 on next request", %{org: org, key: key} do
    assert post_mcp(init_body(), [{"authorization", "Bearer " <> key}]).status == 200

    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})
    assert post_mcp(init_body(), [{"authorization", "Bearer " <> key}]).status == 401
  end
end
```

- [ ] **Step 7: Run to verify passes**

Run: `mix test test/estimate_web/mcp_server_auth_test.exs`
Expected: 4 tests, 0 failures.
If `start_supervised!` fails with `:already_started` (app tree already runs the server in test env), delete the `start_supervised!` line and re-run.

- [ ] **Step 8: Full-suite regression + commit**

Run: `mix test`
Expected: whole suite green (server child must not break unrelated tests).

```bash
mix format
git add -A
git commit -m "feat: MCP server skeleton — KeyValidator, /mcp forward, supervision, auth smoke tests"
```

---

### Task 4: RLS bridge + serializers + customers/search tools

**Files:**
- Create: `lib/estimate_web/mcp/scope.ex`
- Create: `lib/estimate_web/mcp/serializers.ex`
- Create: `lib/estimate_web/mcp/tools/list_customers.ex`
- Create: `lib/estimate_web/mcp/tools/get_customer.ex`
- Create: `lib/estimate_web/mcp/tools/search.ex`
- Modify: `lib/estimate_web/mcp_server.ex` (register components)
- Test: `test/estimate_web/mcp/tools/customers_test.exs`
- Test: `test/estimate_web/mcp/tools/search_test.exs`

**Interfaces:**
- Consumes: `Frame.authorization/1`; `Estimate.CRM.list_customers/1`, `Estimate.CRM.get_customer!/2`; `Estimate.Search.search/3`; `Repo.put_org_id/1`, `Repo.put_user_id/1`; `Estimate.MCPFixtures.mcp_frame/3`.
- Produces:
  - `EstimateWeb.MCP.Scope.claims(frame) :: %{user_id:, org_id:, role:}`
  - `EstimateWeb.MCP.Scope.with_scope(frame, (claims -> result)) :: result` — sets ambient RLS pdict, logs metadata, emits `[:estimate, :mcp, :tool_call]` telemetry (meta: user/org/role; the tool name is logged by anubis' own request handling).
  - `EstimateWeb.MCP.Scope.fetch(frame, fun) :: {:ok, result} | {:error, :not_found}` (rescues `Ecto.NoResultsError` + `Ecto.Query.CastError`).
  - `EstimateWeb.MCP.Serializers.customer/1`, `.search_hit/1`, `.decimal/1`, `.datetime/1`.
  - Tools `list_customers`, `get_customer`, `search`.

- [ ] **Step 1: Write failing tests**

Create `test/estimate_web/mcp/tools/customers_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.CustomersTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{GetCustomer, ListCustomers}

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    %{user: user, org: org, frame: mcp_frame(user, org)}
  end

  defp json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  describe "list_customers" do
    test "returns org customers with search filter and limit", %{org: org, frame: frame} do
      customer_fixture(org, %{"name" => "Acme Corp"})
      customer_fixture(org, %{"name" => "Beta LLC"})

      assert {:reply, response, _} = ListCustomers.execute(%{search: "acme", limit: 50}, frame)
      refute response.isError

      assert %{"customers" => [%{"name" => "Acme Corp"}]} = json_content(response)
    end

    test "cross-org: other org's customers are invisible", %{frame: frame} do
      %{organization: other_org} = user_with_organization_fixture()
      customer_fixture(other_org, %{"name" => "Foreign Inc"})

      assert {:reply, response, _} = ListCustomers.execute(%{limit: 50}, frame)
      assert %{"customers" => []} = json_content(response)
    end
  end

  describe "get_customer" do
    test "returns own customer", %{org: org, frame: frame} do
      customer = customer_fixture(org, %{"name" => "Acme Corp"})

      assert {:reply, response, _} = GetCustomer.execute(%{id: customer.id}, frame)
      refute response.isError
      assert %{"name" => "Acme Corp", "id" => id} = json_content(response)
      assert id == customer.id
    end

    test "foreign org customer → not found (no existence oracle)", %{frame: frame} do
      %{organization: other_org} = user_with_organization_fixture()
      foreign = customer_fixture(other_org)

      assert {:reply, %Response{isError: true}, _} = GetCustomer.execute(%{id: foreign.id}, frame)
    end

    test "malformed id → not found, not a crash", %{frame: frame} do
      assert {:reply, %Response{isError: true}, _} = GetCustomer.execute(%{id: "not-a-uuid"}, frame)
    end
  end
end
```

Create `test/estimate_web/mcp/tools/search_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.SearchTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.Search

  defp json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  test "finds indexed entities in own org only" do
    %{user: user, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org, %{"name" => "Zephyr Industries"})
    Estimate.Search.index_customer(customer)

    %{organization: other_org} = user_with_organization_fixture()
    foreign = customer_fixture(other_org, %{"name" => "Zephyr Foreign"})
    Estimate.Search.index_customer(foreign)

    frame = mcp_frame(user, org)
    assert {:reply, response, _} = Search.execute(%{query: "zephyr", limit: 8}, frame)
    refute response.isError

    assert %{"results" => [hit]} = json_content(response)
    assert hit["title"] =~ "Zephyr Industries"
    assert hit["type"] == "customer"
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/mcp/tools`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Implement Scope**

Create `lib/estimate_web/mcp/scope.ex`:

```elixir
defmodule EstimateWeb.MCP.Scope do
  @moduledoc """
  Bridges anubis auth claims to the app's ambient RLS context.

  Anubis executes tools in per-session processes, not the HTTP request
  process — so the RLS pdict is set here, immediately before every tool
  body, never assumed. DB privileges end up identical to the same user's
  LiveView session (OrgAuth.on_mount does the same two puts).
  """

  require Logger

  alias Anubis.Server.Frame
  alias Estimate.Repo

  def claims(%Frame{} = frame) do
    auth = Frame.authorization(frame)

    %{
      user_id: auth.sub,
      org_id: auth.raw_claims["org_id"],
      role: auth.raw_claims["role"]
    }
  end

  def with_scope(%Frame{} = frame, fun) when is_function(fun, 1) do
    %{user_id: user_id, org_id: org_id} = c = claims(frame)

    Repo.put_org_id(org_id)
    Repo.put_user_id(user_id)
    Logger.metadata(mcp_user_id: user_id, mcp_org_id: org_id)
    :telemetry.execute([:estimate, :mcp, :tool_call], %{count: 1}, c)

    fun.(c)
  end

  @doc "with_scope for lookups: turns NoResultsError/CastError into {:error, :not_found}."
  def fetch(%Frame{} = frame, fun) when is_function(fun, 1) do
    {:ok, with_scope(frame, fun)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end
end
```

- [ ] **Step 4: Implement Serializers**

Create `lib/estimate_web/mcp/serializers.ex`:

```elixir
defmodule EstimateWeb.MCP.Serializers do
  @moduledoc """
  Structs → JSON-native maps for MCP tool responses. Only strings,
  numbers, booleans, nil, lists, maps — Decimal and DateTime are
  stringified so any JSON encoder can handle them.
  """

  def customer(c) do
    %{
      id: c.id,
      key: c.key,
      name: c.name,
      country: c.country,
      website_url: c.website_url,
      description: c.description,
      currency: assoc_code(c.default_currency),
      project_count: if(is_integer(c.project_count), do: c.project_count),
      updated_at: datetime(c.updated_at)
    }
  end

  def search_hit(hit) do
    %{type: hit.type, id: hit.id, title: hit.title, subtitle: hit.subtitle}
  end

  def decimal(nil), do: nil
  def decimal(%Decimal{} = d), do: Decimal.to_string(d)

  def datetime(nil), do: nil
  def datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def assoc_code(%{code: code}), do: code
  def assoc_code(_), do: nil
end
```

- [ ] **Step 5: Implement the three tools**

Create `lib/estimate_web/mcp/tools/list_customers.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.ListCustomers do
  @moduledoc "List the organization's customers: name, key, currency, project count. Optional case-insensitive name filter."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :search, :string, description: "Case-insensitive substring filter on customer name"
    field :limit, :integer, min: 1, max: 200, default: 50
  end

  @impl true
  def execute(params, frame) do
    customers =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.CRM.list_customers(org_id)
      end)
      |> filter_search(params[:search])
      |> Enum.take(params.limit)
      |> Enum.map(&Serializers.customer/1)

    {:reply, Response.json(Response.tool(), %{customers: customers}), frame}
  end

  defp filter_search(customers, nil), do: customers

  defp filter_search(customers, search) do
    down = String.downcase(search)
    Enum.filter(customers, &String.contains?(String.downcase(&1.name), down))
  end
end
```

Create `lib/estimate_web/mcp/tools/get_customer.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.GetCustomer do
  @moduledoc "Fetch one customer by id."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Customer UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn %{org_id: org_id} -> Estimate.CRM.get_customer!(id, org_id) end) do
      {:ok, customer} ->
        {:reply, Response.json(Response.tool(), Serializers.customer(customer)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "customer not found"), frame}
    end
  end
end
```

Create `lib/estimate_web/mcp/tools/search.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.Search do
  @moduledoc "Full-text search across customers, projects and estimations the caller can see."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :query, :string, required: true, min_length: 2, max_length: 200
    field :limit, :integer, min: 1, max: 50, default: 8

    field :types, {:list, :string},
      description: ~s(Optional filter: any of "customer", "project", "estimation")
  end

  @impl true
  def execute(params, frame) do
    opts =
      [limit: params.limit] ++
        case params[:types] do
          nil -> []
          types -> [types: types]
        end

    results =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Search.search(org_id, params.query, opts)
      end)

    {:reply,
     Response.json(Response.tool(), %{results: Enum.map(results, &Serializers.search_hit/1)}),
     frame}
  end
end
```

In `lib/estimate_web/mcp_server.ex`, replace the placeholder comment with:

```elixir
  component EstimateWeb.MCP.Tools.ListCustomers
  component EstimateWeb.MCP.Tools.GetCustomer
  component EstimateWeb.MCP.Tools.Search
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools`
Expected: all pass. If `Frame.authorization/1` returns something unexpected, inspect `deps/anubis_mcp/lib/anubis/server/frame.ex:343` — it reads `frame.context.auth`.

- [ ] **Step 7: Commit**

```bash
mix format
git add -A
git commit -m "feat: MCP RLS bridge (Scope.with_scope) + serializers + customers/search tools"
```

---

### Task 5: Project tools (role-aware)

**Files:**
- Create: `lib/estimate_web/mcp/tools/list_projects.ex`
- Create: `lib/estimate_web/mcp/tools/get_project.ex`
- Modify: `lib/estimate_web/mcp/serializers.ex` (add `project/1`, `project_role/1`, `estimation_summary/1`)
- Modify: `lib/estimate_web/mcp_server.ex` (register)
- Test: `test/estimate_web/mcp/tools/projects_test.exs`

**Interfaces:**
- Consumes: `Portfolio.list_projects(org_id, user_id, role, opts)` (role-aware: owner/admin see all, members only collaborator projects), `Portfolio.get_project_with_roles!(id, org_id)`, `Portfolio.get_project_for_user!(id, user_id)`, `Portfolio.list_project_roles(project_id)`, `EstimationEngine.list_estimations(project_id)`.
- Produces: tools `list_projects` (args: `status?`, `customer_id?`, `limit?`), `get_project` (arg `id`; returns project + roles + estimation summaries). Serializers: `project/1` → `%{id, key, name, status, short_description, customer: %{id, name} | nil, currency, updated_at}`; `project_role/1` → `%{id, name, abbreviation, hourly_rate, pm_overhead, qa_overhead, risk_buffer}`; `estimation_summary/1` → `%{id, name, is_current, updated_at}`.

- [ ] **Step 1: Write failing tests**

Create `test/estimate_web/mcp/tools/projects_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.ProjectsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{GetProject, ListProjects}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)
    project = project_fixture(customer, owner, %{"name" => "Apollo"})
    %{owner: owner, org: org, customer: customer, project: project}
  end

  defp json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  describe "list_projects" do
    test "owner sees all org projects", %{owner: owner, org: org} do
      frame = mcp_frame(owner, org, "owner")

      assert {:reply, response, _} = ListProjects.execute(%{limit: 50}, frame)
      assert %{"projects" => [%{"name" => "Apollo"}]} = json_content(response)
    end

    test "member without collaborator access sees nothing", %{org: org} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      frame = mcp_frame(member, org, "member")

      assert {:reply, response, _} = ListProjects.execute(%{limit: 50}, frame)
      assert %{"projects" => []} = json_content(response)
    end
  end

  describe "get_project" do
    test "owner gets project with roles and estimation summaries", %{
      owner: owner,
      org: org,
      project: project
    } do
      frame = mcp_frame(owner, org, "owner")

      assert {:reply, response, _} = GetProject.execute(%{id: project.id}, frame)
      refute response.isError

      body = json_content(response)
      assert body["name"] == "Apollo"
      assert is_list(body["roles"])
      assert is_list(body["estimations"])
    end

    test "member without access → not found", %{org: org, project: project} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      frame = mcp_frame(member, org, "member")

      assert {:reply, %Response{isError: true}, _} = GetProject.execute(%{id: project.id}, frame)
    end

    test "foreign org project → not found", %{project: project} do
      %{user: outsider, organization: other_org} = user_with_organization_fixture()
      frame = mcp_frame(outsider, other_org, "owner")

      assert {:reply, %Response{isError: true}, _} = GetProject.execute(%{id: project.id}, frame)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/mcp/tools/projects_test.exs`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Serializers additions**

Append to `lib/estimate_web/mcp/serializers.ex` (before the private/leaf helpers):

```elixir
  def project(p) do
    %{
      id: p.id,
      key: p.key,
      name: p.name,
      status: p.status,
      short_description: p.short_description,
      repository_url: p.repository_url,
      customer: project_customer(p.customer),
      currency: assoc_code(p.currency),
      updated_at: datetime(p.updated_at)
    }
  end

  def project_role(r) do
    %{
      id: r.id,
      name: r.name,
      abbreviation: r.abbreviation,
      hourly_rate: decimal(r.hourly_rate),
      pm_overhead: decimal(r.pm_overhead),
      qa_overhead: decimal(r.qa_overhead),
      risk_buffer: decimal(r.risk_buffer)
    }
  end

  def estimation_summary(e) do
    %{id: e.id, name: e.name, is_current: e.is_current, updated_at: datetime(e.updated_at)}
  end

  defp project_customer(%{id: id, name: name}), do: %{id: id, name: name}
  defp project_customer(_), do: nil
```

(If `ProjectRole` lacks any of the overhead fields, drop those keys — check `lib/estimate/portfolio/project_role.ex` and serialize what exists.)

- [ ] **Step 4: Implement tools**

Create `lib/estimate_web/mcp/tools/list_projects.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.ListProjects do
  @moduledoc "List projects visible to the caller (admins: all; members: only projects they collaborate on)."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :status, :enum, values: ["active", "archived", "completed"]
    field :customer_id, :string, description: "Filter by customer UUID"
    field :limit, :integer, min: 1, max: 200, default: 50
  end

  @impl true
  def execute(params, frame) do
    opts = if params[:status], do: [status: params.status], else: []

    projects =
      Scope.with_scope(frame, fn %{org_id: org_id, user_id: user_id, role: role} ->
        Estimate.Portfolio.list_projects(org_id, user_id, role, opts)
      end)
      |> filter_customer(params[:customer_id])
      |> Enum.take(params.limit)
      |> Enum.map(&Serializers.project/1)

    {:reply, Response.json(Response.tool(), %{projects: projects}), frame}
  end

  defp filter_customer(projects, nil), do: projects
  defp filter_customer(projects, customer_id) do
    Enum.filter(projects, &(&1.customer_id == customer_id))
  end
end
```

Create `lib/estimate_web/mcp/tools/get_project.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.GetProject do
  @moduledoc "Fetch one project with its roles and estimation summaries."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Project UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn claims -> load_project(claims, id) end) do
      {:ok, {project, roles, estimations}} ->
        body =
          project
          |> Serializers.project()
          |> Map.put(:detailed_description, project.detailed_description)
          |> Map.put(:roles, Enum.map(roles, &Serializers.project_role/1))
          |> Map.put(:estimations, Enum.map(estimations, &Serializers.estimation_summary/1))

        {:reply, Response.json(Response.tool(), body), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "project not found"), frame}
    end
  end

  # Mirrors the LiveView authz split: admins load by org, members only
  # via their collaborator join (raises NoResultsError otherwise, which
  # Scope.fetch maps to not_found — no existence oracle).
  defp load_project(%{org_id: org_id, user_id: user_id, role: role}, id) do
    project =
      if role in ["owner", "admin"] do
        Estimate.Portfolio.get_project_with_roles!(id, org_id)
      else
        Estimate.Portfolio.get_project_for_user!(id, user_id)
      end

    roles = Estimate.Portfolio.list_project_roles(project.id)
    estimations = Estimate.EstimationEngine.list_estimations(project.id)
    {project, roles, estimations}
  end
end
```

Register in `lib/estimate_web/mcp_server.ex`:

```elixir
  component EstimateWeb.MCP.Tools.ListProjects
  component EstimateWeb.MCP.Tools.GetProject
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/projects_test.exs`
Expected: 5 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
mix format
git add -A
git commit -m "feat: MCP project tools, role-aware visibility mirroring LV authz"
```

---

### Task 6: Estimation tools (list + full tree with totals)

**Files:**
- Create: `lib/estimate_web/mcp/tools/list_estimations.ex`
- Create: `lib/estimate_web/mcp/tools/get_estimation.ex`
- Modify: `lib/estimate_web/mcp/serializers.ex` (add `estimation_tree/1`)
- Modify: `lib/estimate_web/mcp_server.ex` (register)
- Test: `test/estimate_web/mcp/tools/estimations_test.exs`

**Interfaces:**
- Consumes: `EstimationEngine.list_estimations(project_id)` (RLS + soft-delete filtered, preloads `[:roles, :currency]`), `EstimationEngine.get_estimation!(id, org_id)` (preloads currency + ordered roles + epics→tasks→estimates), `EstimationEngine.Calculator` pure functions.
- Produces: tools `list_estimations` (arg `project_id`), `get_estimation` (arg `id`) returning `%{id, name, description, is_current, currency, roles: [...], epics: [%{..., tasks: [%{..., estimates: [%{role_id, hours}]}]}], totals: %{total_hours, total_hours_with_overhead, base_cost, grand_total_with_overhead}}`.

- [ ] **Step 1: Write failing tests**

Create `test/estimate_web/mcp/tools/estimations_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.EstimationsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures
  import Estimate.EstimationEngineFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{GetEstimation, ListEstimations}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)
    project = project_fixture(customer, owner)
    estimation = estimation_fixture(project, %{"name" => "MVP v1"})
    epic = epic_fixture(estimation, %{"name" => "Auth"})
    task_fixture(epic, %{"name" => "Login flow"})

    %{owner: owner, org: org, project: project, estimation: estimation, frame: mcp_frame(owner, org, "owner")}
  end

  defp json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  test "list_estimations returns project estimations", %{project: project, frame: frame} do
    assert {:reply, response, _} = ListEstimations.execute(%{project_id: project.id}, frame)
    assert %{"estimations" => [%{"name" => "MVP v1"}]} = json_content(response)
  end

  test "get_estimation returns full tree with totals", %{estimation: estimation, frame: frame} do
    assert {:reply, response, _} = GetEstimation.execute(%{id: estimation.id}, frame)
    refute response.isError

    body = json_content(response)
    assert body["name"] == "MVP v1"
    assert [%{"name" => "Auth", "tasks" => [%{"name" => "Login flow", "priority" => "must"}]}] = body["epics"]
    assert %{"total_hours" => _, "grand_total_with_overhead" => _} = body["totals"]
  end

  test "foreign org estimation → not found", %{estimation: estimation} do
    %{user: outsider, organization: other_org} = user_with_organization_fixture()
    frame = mcp_frame(outsider, other_org, "owner")

    assert {:reply, %Response{isError: true}, _} = GetEstimation.execute(%{id: estimation.id}, frame)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/mcp/tools/estimations_test.exs`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Serializer**

Append to `lib/estimate_web/mcp/serializers.ex`:

```elixir
  def estimation_tree(est) do
    alias Estimate.EstimationEngine.Calculator

    %{
      id: est.id,
      name: est.name,
      description: est.description,
      is_current: est.is_current,
      currency: assoc_code(est.currency),
      updated_at: datetime(est.updated_at),
      roles: Enum.map(est.roles, &estimation_role/1),
      epics: Enum.map(est.epics, &epic/1),
      totals: %{
        total_hours: decimal(Calculator.calc_total_hours(est.epics)),
        total_hours_with_overhead:
          decimal(Calculator.calc_total_with_overhead_hours(est.epics, est.roles)),
        base_cost: decimal(Calculator.calc_base_cost(est.epics, est.roles)),
        grand_total_with_overhead:
          decimal(Calculator.grand_total_with_overhead(est.epics, est.roles))
      }
    }
  end

  def estimation_role(r) do
    %{
      id: r.id,
      name: r.name,
      abbreviation: r.abbreviation,
      hourly_rate: decimal(r.hourly_rate),
      position: r.position,
      pm_overhead: decimal(r.pm_overhead),
      qa_overhead: decimal(r.qa_overhead),
      risk_buffer: decimal(r.risk_buffer)
    }
  end

  def epic(e) do
    %{
      id: e.id,
      name: e.name,
      description: e.description,
      position: e.position,
      tasks: Enum.map(e.tasks, &task/1)
    }
  end

  def task(t) do
    %{
      id: t.id,
      name: t.name,
      description: t.description,
      position: t.position,
      priority: t.priority,
      estimates:
        Enum.map(t.estimates, fn te ->
          %{role_id: te.estimation_role_id, hours: decimal(te.hours)}
        end)
    }
  end
```

(Move the `alias` to the module top if `mix format`/compiler complains about in-function alias placement.)

- [ ] **Step 4: Implement tools**

Create `lib/estimate_web/mcp/tools/list_estimations.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.ListEstimations do
  @moduledoc "List a project's estimations (non-deleted). RLS hides projects the caller cannot see."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :project_id, :string, required: true, description: "Project UUID"
  end

  @impl true
  def execute(%{project_id: project_id}, frame) do
    case Scope.fetch(frame, fn _claims ->
           Estimate.EstimationEngine.list_estimations(project_id)
         end) do
      {:ok, estimations} ->
        {:reply,
         Response.json(Response.tool(), %{
           estimations: Enum.map(estimations, &Serializers.estimation_summary/1)
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "project not found"), frame}
    end
  end
end
```

Create `lib/estimate_web/mcp/tools/get_estimation.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.GetEstimation do
  @moduledoc "Fetch one estimation with the full epic → task → per-role hours tree plus calculated totals."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Estimation UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn %{org_id: org_id} ->
           Estimate.EstimationEngine.get_estimation!(id, org_id)
         end) do
      {:ok, estimation} ->
        {:reply, Response.json(Response.tool(), Serializers.estimation_tree(estimation)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "estimation not found"), frame}
    end
  end
end
```

Register both in `lib/estimate_web/mcp_server.ex`:

```elixir
  component EstimateWeb.MCP.Tools.ListEstimations
  component EstimateWeb.MCP.Tools.GetEstimation
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/estimations_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
mix format
git add -A
git commit -m "feat: MCP estimation tools — full tree + Calculator totals"
```

---

### Task 7: Templates, role templates, currencies tools

**Files:**
- Create: `lib/estimate_web/mcp/tools/list_templates.ex`
- Create: `lib/estimate_web/mcp/tools/get_template.ex`
- Create: `lib/estimate_web/mcp/tools/list_role_templates.ex`
- Create: `lib/estimate_web/mcp/tools/list_currencies.ex`
- Modify: `lib/estimate_web/mcp/serializers.ex`
- Modify: `lib/estimate_web/mcp_server.ex` (register — completes the 11-tool catalog)
- Test: `test/estimate_web/mcp/tools/catalog_test.exs`

**Interfaces:**
- Consumes: `Templates.list_estimation_templates(org_id)`, `Templates.get_estimation_template!(id, org_id)` (epics+tasks ordered), `Accounts.list_role_templates(org_id)` (preload `rates: :currency`), `Organizations.Currencies.list_currencies(org_id)`.
- Produces: tools `list_templates`, `get_template`, `list_role_templates`, `list_currencies`. Serializers: `template_summary/1`, `template_tree/1`, `role_template/1` (incl. `rates: [%{currency, hourly_rate}]`), `currency/1` (`%{code, name, symbol, symbol_position, exchange_rate, is_main}`).

- [ ] **Step 1: Write failing tests**

Create `test/estimate_web/mcp/tools/catalog_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.CatalogTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.TemplatesFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Response

  alias EstimateWeb.MCP.Tools.{
    GetTemplate,
    ListCurrencies,
    ListRoleTemplates,
    ListTemplates
  }

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    %{user: user, org: org, frame: mcp_frame(user, org, "owner")}
  end

  defp json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  test "list_templates + get_template", %{org: org, frame: frame} do
    template = template_fixture(org, %{"name" => "SaaS Starter"})

    assert {:reply, list_resp, _} = ListTemplates.execute(%{limit: 50}, frame)
    assert %{"templates" => [%{"name" => "SaaS Starter"}]} = json_content(list_resp)

    assert {:reply, get_resp, _} = GetTemplate.execute(%{id: template.id}, frame)
    body = json_content(get_resp)
    assert body["name"] == "SaaS Starter"
    assert is_list(body["epics"])
  end

  test "get_template foreign org → not found", %{frame: frame} do
    %{organization: other_org} = user_with_organization_fixture()
    foreign = template_fixture(other_org)

    assert {:reply, %Response{isError: true}, _} = GetTemplate.execute(%{id: foreign.id}, frame)
  end

  test "list_role_templates returns roles with rates", %{org: org, frame: frame} do
    {:ok, _} = Estimate.Accounts.create_role_template(org.id, %{"name" => "Backend", "abbreviation" => "BE"})

    assert {:reply, response, _} = ListRoleTemplates.execute(%{}, frame)
    assert %{"role_templates" => [%{"name" => "Backend", "abbreviation" => "BE", "rates" => _}]} =
             json_content(response)
  end

  test "list_currencies returns org currencies", %{org: org, frame: frame} do
    {:ok, _} =
      Estimate.Organizations.Currencies.create_currency(org.id, %{
        "code" => "USD",
        "name" => "US Dollar",
        "symbol" => "$",
        "is_main" => true
      })

    assert {:reply, response, _} = ListCurrencies.execute(%{}, frame)
    assert %{"currencies" => [%{"code" => "USD", "is_main" => true}]} = json_content(response)
  end
end
```

(If `create_role_template/2` or `create_currency/2` require more attrs, check their changesets and add the minimum — the test intent is one row per list tool.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/mcp/tools/catalog_test.exs`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Serializers**

Append to `lib/estimate_web/mcp/serializers.ex`:

```elixir
  def template_summary(t) do
    %{id: t.id, name: t.name, description: t.description, updated_at: datetime(t.updated_at)}
  end

  def template_tree(t) do
    template_summary(t)
    |> Map.put(
      :epics,
      Enum.map(t.epics, fn e ->
        %{
          id: e.id,
          name: e.name,
          position: e.position,
          tasks:
            Enum.map(e.tasks, fn task ->
              %{id: task.id, name: task.name, position: task.position}
            end)
        }
      end)
    )
  end

  def role_template(rt) do
    %{
      id: rt.id,
      name: rt.name,
      abbreviation: rt.abbreviation,
      position: rt.position,
      pm_overhead: decimal(rt.pm_overhead),
      qa_overhead: decimal(rt.qa_overhead),
      risk_buffer: decimal(rt.risk_buffer),
      rates:
        Enum.map(rt.rates, fn rate ->
          %{currency: assoc_code(rate.currency), hourly_rate: decimal(rate.hourly_rate)}
        end)
    }
  end

  def currency(c) do
    %{
      code: c.code,
      name: c.name,
      symbol: c.symbol,
      symbol_position: c.symbol_position,
      exchange_rate: decimal(c.exchange_rate),
      is_main: c.is_main
    }
  end
```

(If template epic/task structs carry `description` fields, include them; check `lib/estimate/templates/estimation_template_epic.ex` / `_task.ex`.)

- [ ] **Step 4: Implement four tools**

Create `lib/estimate_web/mcp/tools/list_templates.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.ListTemplates do
  @moduledoc "List the organization's estimation templates."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :limit, :integer, min: 1, max: 200, default: 50
  end

  @impl true
  def execute(params, frame) do
    templates =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Templates.list_estimation_templates(org_id)
      end)
      |> Enum.take(params.limit)
      |> Enum.map(&Serializers.template_summary/1)

    {:reply, Response.json(Response.tool(), %{templates: templates}), frame}
  end
end
```

Create `lib/estimate_web/mcp/tools/get_template.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.GetTemplate do
  @moduledoc "Fetch one estimation template with its epics and tasks."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Template UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn %{org_id: org_id} ->
           Estimate.Templates.get_estimation_template!(id, org_id)
         end) do
      {:ok, template} ->
        {:reply, Response.json(Response.tool(), Serializers.template_tree(template)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "template not found"), frame}
    end
  end
end
```

Create `lib/estimate_web/mcp/tools/list_role_templates.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.ListRoleTemplates do
  @moduledoc "List the organization's role templates with per-currency hourly rates."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    role_templates =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Accounts.list_role_templates(org_id)
      end)
      |> Enum.map(&Serializers.role_template/1)

    {:reply, Response.json(Response.tool(), %{role_templates: role_templates}), frame}
  end
end
```

(If an empty `schema do end` block does not compile in anubis, omit the schema block entirely — components without params are valid.)

Create `lib/estimate_web/mcp/tools/list_currencies.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.ListCurrencies do
  @moduledoc "List the organization's currencies with exchange rates (main currency first)."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  @impl true
  def execute(_params, frame) do
    currencies =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Organizations.Currencies.list_currencies(org_id)
      end)
      |> Enum.map(&Serializers.currency/1)

    {:reply, Response.json(Response.tool(), %{currencies: currencies}), frame}
  end
end
```

Register in `lib/estimate_web/mcp_server.ex` — final component list (11 tools):

```elixir
  component EstimateWeb.MCP.Tools.ListCustomers
  component EstimateWeb.MCP.Tools.GetCustomer
  component EstimateWeb.MCP.Tools.ListProjects
  component EstimateWeb.MCP.Tools.GetProject
  component EstimateWeb.MCP.Tools.ListEstimations
  component EstimateWeb.MCP.Tools.GetEstimation
  component EstimateWeb.MCP.Tools.ListTemplates
  component EstimateWeb.MCP.Tools.GetTemplate
  component EstimateWeb.MCP.Tools.ListRoleTemplates
  component EstimateWeb.MCP.Tools.ListCurrencies
  component EstimateWeb.MCP.Tools.Search
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/catalog_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
mix format
git add -A
git commit -m "feat: MCP templates/role-templates/currencies tools — 11-tool catalog complete"
```

---

### Task 8: End-to-end HTTP integration

**Files:**
- Test: `test/estimate_web/mcp_server_integration_test.exs`

**Interfaces:**
- Consumes: everything above; anubis session flow (initialize → `mcp-session-id` header → notifications/initialized → tools/list, tools/call).
- Produces: proof that the whole pipe works and cross-org isolation holds over HTTP.

- [ ] **Step 1: Write the integration test**

Create `test/estimate_web/mcp_server_integration_test.exs`:

```elixir
defmodule EstimateWeb.MCPServerIntegrationTest do
  use Estimate.DataCase, async: false

  import Plug.Conn
  import Plug.Test
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Transport.StreamableHTTP

  @plug_opts StreamableHTTP.Plug.init(server: EstimateWeb.MCPServer)

  setup do
    start_supervised!({EstimateWeb.MCPServer, transport: {:streamable_http, start: true}})

    %{user: user, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org, %{"name" => "Acme Corp"})
    {key, _} = mcp_api_key_fixture(user, org)

    # Foreign org data that must never leak
    %{organization: other_org} = user_with_organization_fixture()
    foreign_customer = customer_fixture(other_org, %{"name" => "Foreign Inc"})

    %{key: key, org: org, customer: customer, foreign_customer: foreign_customer}
  end

  defp post_mcp(body, headers) do
    conn =
      conn(:post, "/", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    headers
    |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> StreamableHTTP.Plug.call(@plug_opts)
  end

  defp initialize_session(key) do
    conn =
      post_mcp(
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{
            "protocolVersion" => "2025-06-18",
            "clientInfo" => %{"name" => "test", "version" => "1.0.0"},
            "capabilities" => %{}
          }
        },
        [{"authorization", "Bearer " <> key}]
      )

    assert conn.status == 200
    [session_id] = get_resp_header(conn, "mcp-session-id")

    post_mcp(
      %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
      [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
    )

    session_id
  end

  defp call_tool(key, session_id, name, args, id \\ 2) do
    conn =
      post_mcp(
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "method" => "tools/call",
          "params" => %{"name" => name, "arguments" => args}
        },
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 200
    conn.resp_body
  end

  test "tools/list exposes the 11-tool catalog", %{key: key} do
    session_id = initialize_session(key)

    conn =
      post_mcp(
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}},
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 200

    for tool <- ~w(list_customers get_customer list_projects get_project list_estimations
                   get_estimation list_templates get_template list_role_templates
                   list_currencies search) do
      assert conn.resp_body =~ ~s("#{tool}")
    end
  end

  test "tools/call list_customers returns own org data over HTTP", %{key: key} do
    session_id = initialize_session(key)
    body = call_tool(key, session_id, "list_customers", %{})

    assert body =~ "Acme Corp"
    refute body =~ "Foreign Inc"
  end

  test "cross-org isolation: foreign customer id → not found", %{
    key: key,
    foreign_customer: foreign
  } do
    session_id = initialize_session(key)
    body = call_tool(key, session_id, "get_customer", %{"id" => foreign.id})

    assert body =~ "customer not found"
    refute body =~ "Foreign Inc"
  end

  test "kill switch: disabling org 401s mid-session", %{key: key, org: org} do
    session_id = initialize_session(key)
    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})

    conn =
      post_mcp(
        %{"jsonrpc" => "2.0", "id" => 3, "method" => "tools/list", "params" => %{}},
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 401
  end
end
```

- [ ] **Step 2: Run it**

Run: `mix test test/estimate_web/mcp_server_integration_test.exs`
Expected: 4 tests, 0 failures.
If the tools/call response body is an SSE frame (`data: {...}`), the `=~` assertions still hold — they check substrings, not JSON shape. If `start_supervised!` errors `:already_started`, drop that line (see Task 3 Step 7).

- [ ] **Step 3: Commit**

```bash
mix format
git add -A
git commit -m "test: MCP end-to-end HTTP integration — catalog, cross-org isolation, kill switch"
```

---

### Task 9: Settings UI — `/settings/mcp`

**Files:**
- Create: `lib/estimate_web/live/settings_live/mcp.ex`
- Modify: `lib/estimate_web/router.ex` (route)
- Modify: `lib/estimate_web/components/layouts/app.html.heex` (sidebar link)
- Test: `test/estimate_web/live/settings_live/mcp_test.exs`

**Interfaces:**
- Consumes: `Organizations.update_mcp_settings/2`, `Estimate.MCP.{generate_api_key/2, get_api_key/2, revoke_api_key/2}`, assigns from live_session `:org_scoped` (`:current_user`, `:current_organization`, `:current_membership`, `:org_id`), `admin?/1` + `require_admin/2` from `EstimateWeb.AuthHelpers` (already imported via `use EstimateWeb, :live_view`).
- Produces: route `live "/settings/mcp", SettingsLive.Mcp, :index`; page with admin toggle block + personal key block; `:settings_page` assign `:mcp`.

Behavior contract:
- ALL members may open the page (unlike the AI page — no mount redirect).
- Only admins see/use the enable toggle (`require_admin` guards the event).
- Personal key block renders only when `@current_organization.mcp_enabled`; otherwise members see a "disabled by admin" note.
- Generated plaintext key is shown once in a highlighted panel (with the `claude mcp add` snippet) and disappears on dismiss/remount; only `key_prefix`, created and last-used dates persist on screen.

- [ ] **Step 1: Write failing LV tests**

Create `test/estimate_web/live/settings_live/mcp_test.exs`:

```elixir
defmodule EstimateWeb.SettingsLive.McpTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  alias Estimate.MCP
  alias Estimate.Organizations

  setup :register_and_log_in_org_owner

  defp mcp_path(org), do: ~p"/org/#{org.id}/settings/mcp"

  describe "admin toggle" do
    test "owner enables MCP (org default is disabled)", %{conn: conn, org: org} do
      refute org.mcp_enabled

      {:ok, lv, html} = live(conn, mcp_path(org))
      assert html =~ "MCP Server"

      lv |> element("button", "Enable") |> render_click()
      assert Estimate.Repo.reload!(org).mcp_enabled
    end

    test "member sees no toggle and cannot flip it", %{conn: _conn, org: org} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      conn = log_in_user(build_conn(), member)

      {:ok, lv, html} = live(conn, mcp_path(org))
      refute html =~ "Enable"

      # Event forged directly must be rejected by require_admin.
      render_click(lv, "toggle_mcp", %{})
      refute Estimate.Repo.reload!(org).mcp_enabled
    end
  end

  describe "personal key" do
    setup %{org: org} do
      {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
      %{org: org}
    end

    test "generate shows plaintext once; remount shows only prefix", %{conn: conn, user: user, org: org} do
      {:ok, lv, _} = live(conn, mcp_path(org))

      html = lv |> element("button", "Generate API Key") |> render_click()
      assert [_, plaintext] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html)
      assert {:ok, _} = MCP.verify_api_key(plaintext)

      {:ok, _lv, remount_html} = live(conn, mcp_path(org))
      refute remount_html =~ plaintext
      assert remount_html =~ String.slice(plaintext, 0, 12)
      assert MCP.get_api_key(user.id, org.id)
    end

    test "regenerate invalidates the old key", %{conn: conn, org: org} do
      {:ok, lv, _} = live(conn, mcp_path(org))

      html1 = lv |> element("button", "Generate API Key") |> render_click()
      [_, key1] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html1)

      html2 = lv |> element("button", "Regenerate") |> render_click()
      [_, key2] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html2)

      assert key1 != key2
      assert {:error, :invalid_key} = MCP.verify_api_key(key1)
      assert {:ok, _} = MCP.verify_api_key(key2)
    end

    test "revoke deletes the key", %{conn: conn, user: user, org: org} do
      {:ok, lv, _} = live(conn, mcp_path(org))
      lv |> element("button", "Generate API Key") |> render_click()

      lv |> element("button", "Revoke") |> render_click()
      assert MCP.get_api_key(user.id, org.id) == nil
    end

    test "disabled org: member sees notice, no generate button", %{conn: conn, org: org} do
      {:ok, _} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})

      {:ok, _lv, html} = live(conn, mcp_path(org))
      assert html =~ "disabled"
      refute html =~ "Generate API Key"
    end
  end
end
```

(Plaintext key length: `Base.url_encode64` of 32 bytes without padding = 43 chars, hence the regex. `register_and_log_in_org_owner` provides `%{conn, user, org}`.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: FAIL — no route / module.

- [ ] **Step 3: Route + sidebar**

In `lib/estimate_web/router.ex`, after the `live "/settings/email"` line, add:

```elixir
      live "/settings/mcp", SettingsLive.Mcp, :index
```

In `lib/estimate_web/components/layouts/app.html.heex`, in the Settings sidebar section (~L71–105), after the Email `sidebar_child_link` (note: NOT admin-gated — every member manages their own key):

```heex
<.sidebar_child_link
  href={~p"/org/#{@org_id}/settings/mcp"}
  label="MCP"
  active={assigns[:settings_page] == :mcp}
/>
```

(Match the exact attribute style of the sibling links in that file.)

- [ ] **Step 4: Implement the LiveView**

Create `lib/estimate_web/live/settings_live/mcp.ex`:

```elixir
defmodule EstimateWeb.SettingsLive.Mcp do
  use EstimateWeb, :live_view

  alias Estimate.MCP
  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">MCP Server</h1>
        <p class="mt-1 text-base-content/60">
          Expose read-only org data to MCP clients (Claude Code, Claude Desktop, Cursor…)
        </p>
      </div>

      <div :if={admin?(@current_membership)} class="bg-base-100 border border-base-300 rounded-xl p-6 mb-6">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-sm font-medium text-base-content">
              {if @current_organization.mcp_enabled, do: "MCP server is enabled", else: "MCP server is disabled"}
            </h2>
            <p class="mt-1 text-sm text-base-content/60">
              Members authenticate with personal API keys that inherit their access. Disabling
              instantly rejects every key.
            </p>
            <p :if={@current_organization.mcp_enabled} class="mt-2 text-sm font-mono text-base-content/70">
              {@mcp_url}
            </p>
          </div>
          <button
            phx-click="toggle_mcp"
            class={[
              "px-4 py-1.5 text-sm rounded-md font-medium transition-colors",
              if(@current_organization.mcp_enabled,
                do: "bg-error/10 text-error hover:bg-error/20",
                else: "bg-neutral text-neutral-content hover:bg-neutral/90"
              )
            ]}
          >
            {if @current_organization.mcp_enabled, do: "Disable", else: "Enable"}
          </button>
        </div>
      </div>

      <div :if={!@current_organization.mcp_enabled} class="bg-base-100 border border-base-300 rounded-xl p-6">
        <p class="text-sm text-base-content/60">
          The MCP server is disabled for this organization. Ask an admin to enable it.
        </p>
      </div>

      <div :if={@current_organization.mcp_enabled} class="bg-base-100 border border-base-300 rounded-xl p-6">
        <h2 class="text-sm font-medium text-base-content mb-1">Your API key</h2>
        <p class="text-sm text-base-content/60 mb-4">
          The key acts as you: it sees exactly what you see in the app.
        </p>

        <div :if={@new_key} class="mb-4 p-4 bg-warning/10 border border-warning/30 rounded-lg">
          <p class="text-sm font-medium text-base-content mb-2">
            Copy your key now — it will not be shown again.
          </p>
          <code class="block font-mono text-sm break-all select-all mb-3">{@new_key}</code>
          <p class="text-xs font-medium text-base-content/60 mb-1">Add to Claude Code:</p>
          <code class="block font-mono text-xs break-all select-all mb-3">
            claude mcp add --transport http estimate {@mcp_url} --header "Authorization: Bearer {@new_key}"
          </code>
          <button phx-click="dismiss_new_key" class="text-sm text-base-content/60 hover:text-base-content">
            Dismiss
          </button>
        </div>

        <div :if={@api_key} class="flex items-center justify-between">
          <div class="text-sm text-base-content/70 font-mono">
            {@api_key.key_prefix}…
            <span class="ml-3 font-sans text-base-content/50">
              created {Calendar.strftime(@api_key.inserted_at, "%Y-%m-%d")}
            </span>
            <span :if={@api_key.last_used_at} class="ml-3 font-sans text-base-content/50">
              last used {Calendar.strftime(@api_key.last_used_at, "%Y-%m-%d %H:%M")} UTC
            </span>
          </div>
          <div class="flex items-center gap-2">
            <button
              phx-click="generate_key"
              data-confirm="This invalidates your current key. Continue?"
              class="px-3 py-1.5 text-sm rounded-md border border-base-300 hover:bg-base-200 transition-colors"
            >
              Regenerate
            </button>
            <button
              phx-click="revoke_key"
              data-confirm="Revoke your API key?"
              class="px-3 py-1.5 text-sm rounded-md text-error hover:bg-error/10 transition-colors"
            >
              Revoke
            </button>
          </div>
        </div>

        <button
          :if={@api_key == nil}
          phx-click="generate_key"
          class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
        >
          Generate API Key
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, org_id: org_id} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "MCP Server")
     |> assign(:active_tab, :settings)
     |> assign(:settings_page, :mcp)
     |> assign(:mcp_url, url(~p"/mcp"))
     |> assign(:api_key, MCP.get_api_key(user.id, org_id))
     |> assign(:new_key, nil)}
  end

  @impl true
  def handle_event("toggle_mcp", _params, socket) do
    require_admin(socket, fn ->
      org = socket.assigns.current_organization

      case Organizations.update_mcp_settings(org, %{mcp_enabled: !org.mcp_enabled}) do
        {:ok, org} ->
          {:noreply,
           socket
           |> assign(:current_organization, org)
           |> put_flash(:info, if(org.mcp_enabled, do: "MCP server enabled", else: "MCP server disabled"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update MCP settings")}
      end
    end)
  end

  def handle_event("generate_key", _params, socket) do
    %{current_user: user, org_id: org_id} = socket.assigns

    case MCP.generate_api_key(user.id, org_id) do
      {:ok, {plaintext, api_key}} ->
        {:noreply, socket |> assign(:api_key, api_key) |> assign(:new_key, plaintext)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate API key")}
    end
  end

  def handle_event("revoke_key", _params, socket) do
    %{current_user: user, org_id: org_id} = socket.assigns
    MCP.revoke_api_key(user.id, org_id)

    {:noreply,
     socket
     |> assign(:api_key, nil)
     |> assign(:new_key, nil)
     |> put_flash(:info, "API key revoked")}
  end

  def handle_event("dismiss_new_key", _params, socket) do
    {:noreply, assign(socket, :new_key, nil)}
  end
end
```

- [ ] **Step 5: Run LV tests to verify they pass**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: 6 tests, 0 failures.
Note: `data-confirm` does not block `render_click` in tests. If the `element("button", "Enable")` selector is ambiguous, scope it: `element("button[phx-click=toggle_mcp]")`.

- [ ] **Step 6: Commit**

```bash
mix format
git add -A
git commit -m "feat: /settings/mcp page — admin toggle + show-once personal API key"
```

---

### Task 10: Final verification sweep

**Files:** none new.

- [ ] **Step 1: Full suite + format check**

Run: `mix format --check-formatted && mix compile --warnings-as-errors && mix test`
Expected: everything green. Fix anything that isn't, then re-run.

- [ ] **Step 2: Spec cross-check**

Confirm each spec section has landed: dep ✓ (T1), migrations + RLS policy ✓ (T1), key lifecycle + verify ✓ (T2), validator + `aud` handling ✓ (T3), `/mcp` forward + supervision ✓ (T3), `with_scope` RLS bridge ✓ (T4), 11 tools ✓ (T4–T7), no-existence-oracle errors ✓ (T4–T7 tests), cross-org isolation over HTTP + kill switch ✓ (T8), settings page with show-once key + admin toggle ✓ (T9), `last_used_at` throttle ✓ (T2), telemetry + logger metadata ✓ (T4).

- [ ] **Step 3: Manual dev verification (optional but recommended)**

Start the dev server, log in with the seed user, enable MCP in `/settings/mcp`, generate a key, then:

```bash
curl -s -X POST http://localhost:4000/mcp \
  -H "content-type: application/json" \
  -H "accept: application/json, text/event-stream" \
  -H "authorization: Bearer est_..." \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"curl","version":"0"},"capabilities":{}}}'
```

Expected: 200 with `serverInfo.name == "estimate"`. Without the header: 401.

- [ ] **Step 4: Commit any stragglers**

```bash
git status
# commit only if something changed
```
