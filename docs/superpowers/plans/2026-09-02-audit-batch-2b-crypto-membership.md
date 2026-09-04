# Audit Batch 2b — Crypto + Membership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the TOTP replay guard database-backed (cross-node), add a rotatable dedicated encryption key with per-row key versions, and close the membership gaps: CSPRNG invite codes, atomic invite claim, ownership transfer, leave organization, context-level role enforcement, pending-only join approval, membership-checked collaborators.

**Architecture:** `Estimate.Accounts.Totp` gains `verify_code/3` that uses `NimbleTOTP.valid?(..., since: user.totp_last_used_at)` and persists the timestamp, replacing the ETS `:totp_replay` bucket. `Estimate.Encryption` becomes a versioned key ring (`v1` = derived from `SECRET_KEY_BASE`, `v2` = `ENCRYPTION_KEY` env) with `*_key_version` columns and lazy re-encryption. Membership changes are context functions in `Estimate.Organizations` with one Multi each, surfaced through the existing members roster and org settings LiveViews.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8.3 / LiveView 1.1 / Ecto 3.13 / Postgres 17 / nimble_totp 1.0.

**Spec:** `docs/superpowers/specs/2026-09-02-audit-batch-2-security-design.md`, section "2b. Crypto + membership".

## Global Constraints

- Additive migrations only (new columns with defaults/backfill). No drops, renames, type changes.
- TDD per task: failing test first, run it, implement, run green, commit. `mix test <file>` runs one file (the alias migrates first).
- Diverge-then-assert tests: forbidden state in place → rejection → DB unchanged.
- Exact copy: "Transfer ownership before leaving.", "Transfer your projects before leaving.", "Not authorized", "Invalid role", "Ownership transferred", "You left the organization".
- Roles: `Membership.assignable_roles()` is `["admin", "member"]`; `"owner"` is reachable only via organization creation and `transfer_ownership/3`.
- Do not touch mail/reset/confirmation code paths.
- Commit signing uses 1Password; on a signing error wait 30 s and retry up to 3 times.
- Finish with `mix precommit` green.

---

### Task 1: DB-backed TOTP replay guard

**Files:**
- Create: `priv/repo/migrations/20260902140000_add_totp_last_used_at_to_users.exs`
- Modify: `lib/estimate/accounts/user.ex` (field), `lib/estimate/accounts/totp.ex`
- Modify: `lib/estimate_web/controllers/user_session_controller.ex` (`verify_totp/2`), `lib/estimate_web/live/user_live/account_settings.ex` (`disable_totp`)
- Modify: `lib/estimate/rate_limit.ex`, `config/config.exs`, `config/runtime.exs`, `README.md` (remove `:totp_replay`)
- Test: `test/estimate/accounts/totp_test.exs` (create), `test/estimate_web/controllers/user_session_controller_test.exs` (adjust), `test/estimate/rate_limit_test.exs` (remove replay test)

**Interfaces:**
- Produces: `Totp.verify_code(%User{}, secret, code) :: {:ok, %User{}} | :error` — valid only if the code is newer than `user.totp_last_used_at` (NimbleTOTP `since:`); on success persists `totp_last_used_at = now` and returns the updated user. `Totp.verify_code_or_backup(%User{}, secret, code) :: {:ok, %User{}} | :error` (TOTP first, then single-use backup code). `Totp.valid_code?/2` stays for enrollment (no user row yet).
- Removes: `RateLimit` bucket `:totp_replay`, controller `replay_allowed/2`.

- [ ] **Step 1: Failing tests**

`test/estimate/accounts/totp_test.exs`:
```elixir
defmodule Estimate.Accounts.TotpTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures
  alias Estimate.Accounts.Totp

  test "verify_code accepts a fresh code once and refuses the same code again (DB-backed)" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    code = valid_totp_code(secret)

    assert {:ok, user} = Totp.verify_code(user, secret, code)
    assert %DateTime{} = user.totp_last_used_at

    # reload from DB: the guard must not depend on process state
    fresh = Estimate.Accounts.get_user!(user.id)
    assert :error = Totp.verify_code(fresh, secret, code)
  end

  test "verify_code refuses garbage" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    assert :error = Totp.verify_code(user, secret, "000000")
    refute Estimate.Accounts.get_user!(user.id).totp_last_used_at
  end

  test "verify_code_or_backup falls back to a single-use backup code" do
    %{user: user, secret: secret, backup_codes: [code | _]} = user_with_totp_fixture()
    assert {:ok, user} = Totp.verify_code_or_backup(user, secret, code)
    assert :error = Totp.verify_code_or_backup(user, secret, code)
  end

  test "users.totp_last_used_at exists and is nullable" do
    %{rows: [[nullable]]} =
      Repo.query!("SELECT is_nullable FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'totp_last_used_at'")
    assert nullable == "YES"
  end
end
```

`user_session_controller_test.exs`: the existing "a valid TOTP code cannot be replayed" test must keep passing after the bucket is removed (it now proves the DB guard). Add nothing.

`rate_limit_test.exs`: delete the `totp_replay` test.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/accounts/totp_test.exs`
Expected: FAIL — `verify_code/3` undefined, column missing.

- [ ] **Step 3: Migration + schema**

```elixir
defmodule Estimate.Repo.Migrations.AddTotpLastUsedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :totp_last_used_at, :utc_datetime
    end
  end
end
```
`user.ex`: `field :totp_last_used_at, :utc_datetime` after `totp_backup_codes`.

- [ ] **Step 4: Totp**

```elixir
  @doc """
  Verifies a TOTP code for an enrolled user. A code is accepted only if it is
  newer than the last accepted one (`since:`), so a captured code cannot be
  replayed on any node; the acceptance timestamp is persisted.
  """
  def verify_code(%User{} = user, secret, code) do
    if NimbleTOTP.valid?(secret, code, since: user.totp_last_used_at) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      user |> change(%{totp_last_used_at: now}) |> Repo.update()
    else
      :error
    end
  end

  def verify_code_or_backup(%User{} = user, secret, code) do
    case verify_code(user, secret, code) do
      {:ok, user} -> {:ok, user}
      :error -> consume_backup_code(user, code)
    end
  end
```
Delete `valid_code_or_backup?/3`. Keep `valid_code?/2` (enrollment).

- [ ] **Step 5: Callers**

`user_session_controller.ex` `verify_totp/2`:
```elixir
        with :ok <- attempt_allowed(user),
             {:ok, secret} <- Totp.get_decrypted_secret(user),
             {:ok, user} <- Totp.verify_code_or_backup(user, secret, code) do
```
Delete `replay_allowed/2` and its comment; update the `else` catch-all name to `_invalid`. `account_settings.ex` `disable_totp`: `{:ok, _user} <- Totp.verify_code_or_backup(user, secret, String.trim(code))`.

- [ ] **Step 6: Remove the bucket**

`rate_limit.ex`: drop `totp_replay` from `@windows`, `@defaults`, `@type bucket`, and any `normalize({a, b})` comment that mentions it (keep the tuple clause; it is harmless). `config/config.exs` and `config/runtime.exs`: remove the `totp_replay` lines. README: remove `RATE_LIMIT_TOTP_REPLAY` from the env row and rewrite the "Rate limiting is per-node" bullet: the TOTP replay guard is now DB-backed (`users.totp_last_used_at`), rate limits remain per-node.

- [ ] **Step 7: Run tests, commit**

Run: `mix test test/estimate/accounts/totp_test.exs test/estimate_web/controllers/user_session_controller_test.exs test/estimate_web/live/user_live/ test/estimate/rate_limit_test.exs`
Expected: PASS.

```bash
git add priv/repo/migrations/20260902140000_add_totp_last_used_at_to_users.exs lib/estimate/accounts/user.ex lib/estimate/accounts/totp.ex lib/estimate_web/controllers/user_session_controller.ex lib/estimate_web/live/user_live/account_settings.ex lib/estimate/rate_limit.ex config/config.exs config/runtime.exs README.md test/estimate/accounts/totp_test.exs test/estimate/rate_limit_test.exs
git commit -m "feat(security): DB-backed TOTP replay guard (totp_last_used_at); drop ETS replay bucket"
```

---

### Task 2: Versioned encryption key ring

**Files:**
- Create: `priv/repo/migrations/20260902141000_add_encryption_key_versions.exs`
- Modify: `lib/estimate/encryption.ex`, `lib/estimate/application.ex`, `config/runtime.exs`, `config/test.exs`, `README.md`
- Modify: `lib/estimate/accounts/user.ex`, `lib/estimate/accounts/organization.ex` (fields + changesets), `lib/estimate/accounts/totp.ex`, `lib/estimate/organizations.ex` (`decrypt_field/3`)
- Test: `test/estimate/encryption_test.exs` (create)

**Interfaces:**
- Produces: `Encryption.encrypt(plaintext) :: {:ok, nonce, ciphertext, key_version :: pos_integer()}`; `Encryption.decrypt(nonce, ciphertext, key_version) :: {:ok, plaintext} | {:error, :decrypt_failed | :unknown_key_version}`; `Encryption.current_version() :: pos_integer()`; `Encryption.load_keys() :: :ok` (builds the ring into `:persistent_term`; called from `Application.start/2` and by tests after changing config). Config: `config :estimate, Estimate.Encryption, key: base64_or_nil` (runtime.exs from `ENCRYPTION_KEY`).
- Columns: `users.totp_key_version`, `organizations.openrouter_key_version`, `organizations.smtp_key_version` — `:integer, null: false, default: 1`.
- `Totp.get_decrypted_secret/1` and `Organizations.get_decrypted_api_key/1`, `get_decrypted_smtp_password/1` lazily re-encrypt with the current key when the row's version is older (persisting the new ciphertext, nonce, version).

- [ ] **Step 1: Failing tests**

```elixir
defmodule Estimate.EncryptionTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.{Encryption, Organizations, Repo}
  alias Estimate.Accounts.Totp

  @v2 Base.encode64(:crypto.strong_rand_bytes(32))

  setup do
    prev = Application.get_env(:estimate, Estimate.Encryption, [])
    on_exit(fn ->
      Application.put_env(:estimate, Estimate.Encryption, prev)
      Encryption.load_keys()
    end)
    :ok
  end

  defp set_key(nil), do: Application.put_env(:estimate, Estimate.Encryption, key: nil)
  defp set_key(k), do: Application.put_env(:estimate, Estimate.Encryption, key: k)

  test "without ENCRYPTION_KEY the ring has only v1" do
    set_key(nil); Encryption.load_keys()
    assert Encryption.current_version() == 1
    {:ok, n, ct, 1} = Encryption.encrypt("s3cret")
    assert {:ok, "s3cret"} = Encryption.decrypt(n, ct, 1)
    assert {:error, :unknown_key_version} = Encryption.decrypt(n, ct, 2)
  end

  test "with ENCRYPTION_KEY new data is v2 and v1 data still decrypts" do
    set_key(nil); Encryption.load_keys()
    {:ok, n1, ct1, 1} = Encryption.encrypt("old")
    set_key(@v2); Encryption.load_keys()
    assert Encryption.current_version() == 2
    {:ok, n2, ct2, 2} = Encryption.encrypt("new")
    assert {:ok, "old"} = Encryption.decrypt(n1, ct1, 1)
    assert {:ok, "new"} = Encryption.decrypt(n2, ct2, 2)
    assert {:error, :decrypt_failed} = Encryption.decrypt(n2, ct2, 1)
  end

  test "TOTP secret is lazily re-encrypted to the current key on read" do
    set_key(nil); Encryption.load_keys()
    %{user: user, secret: secret} = user_with_totp_fixture()
    assert user.totp_key_version == 1
    set_key(@v2); Encryption.load_keys()
    assert {:ok, ^secret} = Totp.get_decrypted_secret(user)
    reloaded = Estimate.Accounts.get_user!(user.id)
    assert reloaded.totp_key_version == 2
    assert {:ok, ^secret} = Totp.get_decrypted_secret(reloaded)
  end

  test "org API key is lazily re-encrypted on read" do
    set_key(nil); Encryption.load_keys()
    %{organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_ai_settings(org, %{"openrouter_api_key" => "sk-or-abc123456789"})
    assert org.openrouter_key_version == 1
    set_key(@v2); Encryption.load_keys()
    assert Organizations.get_decrypted_api_key(org) == "sk-or-abc123456789"
    assert Repo.reload!(org).openrouter_key_version == 2
  end

  test "key version columns exist with default 1" do
    for {t, c} <- [{"users", "totp_key_version"}, {"organizations", "openrouter_key_version"}, {"organizations", "smtp_key_version"}] do
      %{rows: [[default, nullable]]} =
        Repo.query!("SELECT column_default, is_nullable FROM information_schema.columns WHERE table_name = $1 AND column_name = $2", [t, c])
      assert default == "1" and nullable == "NO"
    end
  end
end
```

Check `Organization.ai_settings_changeset/2` casts `openrouter_api_key` (virtual) — it does (`encrypt_api_key/1`); the test uses the string key form the LiveView sends.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/encryption_test.exs`
Expected: FAIL — arity/undefined functions, columns missing.

- [ ] **Step 3: Migration**

```elixir
defmodule Estimate.Repo.Migrations.AddEncryptionKeyVersions do
  use Ecto.Migration

  # All existing ciphertexts were produced with key v1 (derived from SECRET_KEY_BASE).
  def change do
    alter table(:users) do
      add :totp_key_version, :integer, null: false, default: 1
    end

    alter table(:organizations) do
      add :openrouter_key_version, :integer, null: false, default: 1
      add :smtp_key_version, :integer, null: false, default: 1
    end
  end
end
```
Schemas: `field :totp_key_version, :integer, default: 1` (User); `field :openrouter_key_version, :integer, default: 1` and `field :smtp_key_version, :integer, default: 1` (Organization).

- [ ] **Step 4: Encryption module**

```elixir
defmodule Estimate.Encryption do
  @moduledoc """
  AES-256-GCM with a versioned key ring.

  * v1 — derived from `SECRET_KEY_BASE` (legacy; rotating the Phoenix secret used
    to brick every stored secret).
  * v2 — `ENCRYPTION_KEY` (base64 of 32 random bytes), when configured.

  `encrypt/1` always uses the newest key and returns its version; `decrypt/3`
  uses the version stored beside the ciphertext. Readers re-encrypt lazily
  (see `Estimate.Accounts.Totp` / `Estimate.Organizations`) and
  `mix estimate.rotate_encryption` re-encrypts everything eagerly.
  """

  @aad "estimate-encryption"
  @term {__MODULE__, :ring}

  @spec load_keys() :: :ok
  def load_keys do
    v1 =
      EstimateWeb.Endpoint.config(:secret_key_base)
      |> Plug.Crypto.KeyGenerator.generate("estimate-encryption-v1", length: 32)

    ring =
      case Application.get_env(:estimate, __MODULE__, [])[:key] do
        nil -> %{1 => v1}
        "" -> %{1 => v1}
        b64 -> %{1 => v1, 2 => decode_key!(b64)}
      end

    :persistent_term.put(@term, ring)
    :ok
  end

  def current_version, do: ring() |> Map.keys() |> Enum.max()

  @spec encrypt(binary()) :: {:ok, binary(), binary(), pos_integer()}
  def encrypt(plaintext) when is_binary(plaintext) do
    version = current_version()
    key = Map.fetch!(ring(), version)
    nonce = :crypto.strong_rand_bytes(12)
    {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, @aad, true)
    {:ok, nonce, ct <> tag, version}
  end

  @spec decrypt(binary(), binary(), pos_integer()) ::
          {:ok, binary()} | {:error, :decrypt_failed | :unknown_key_version}
  def decrypt(nonce, ct_with_tag, version)
      when is_binary(nonce) and is_binary(ct_with_tag) and is_integer(version) do
    case Map.fetch(ring(), version) do
      :error ->
        {:error, :unknown_key_version}

      {:ok, key} ->
        size = byte_size(ct_with_tag) - 16
        <<ct::binary-size(size), tag::binary-size(16)>> = ct_with_tag

        case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ct, @aad, tag, false) do
          pt when is_binary(pt) -> {:ok, pt}
          :error -> {:error, :decrypt_failed}
        end
    end
  end

  def decrypt(_, _, _), do: {:error, :decrypt_failed}

  defp ring do
    case :persistent_term.get(@term, nil) do
      nil -> (load_keys(); :persistent_term.get(@term))
      ring -> ring
    end
  end

  defp decode_key!(b64) do
    case Base.decode64(b64) do
      {:ok, <<key::binary-size(32)>>} -> key
      _ -> raise ArgumentError, "ENCRYPTION_KEY must be base64 of exactly 32 bytes"
    end
  end
end
```

`application.ex`: after children start? No — `load_keys/0` needs `EstimateWeb.Endpoint.config/1`, which reads app env (available before the Endpoint process starts). Call `Estimate.Encryption.load_keys()` as the first line of `start/2`. `config/runtime.exs` prod block: `config :estimate, Estimate.Encryption, key: System.get_env("ENCRYPTION_KEY")`. `config/test.exs`: `config :estimate, Estimate.Encryption, key: nil`. README env table row: `ENCRYPTION_KEY` (prod, optional; base64 of 32 bytes, `openssl rand -base64 32`; when set, new secrets use it and old ones are re-encrypted on read or via `mix estimate.rotate_encryption`).

- [ ] **Step 5: Call sites**

`totp.ex`:
```elixir
  def encrypt_secret(secret) do
    {:ok, nonce, ciphertext, version} = Encryption.encrypt(secret)
    {nonce, ciphertext, version}
  end

  def enable_totp(%User{} = user, secret, backup_hashes) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {nonce, ciphertext, version} = encrypt_secret(secret)
    ...
    |> change(%{encrypted_totp_secret: ciphertext, totp_secret_nonce: nonce, totp_key_version: version, totp_enabled_at: now, totp_backup_codes: Jason.encode!(backup_hashes)})
  end

  def get_decrypted_secret(%User{totp_secret_nonce: nonce, encrypted_totp_secret: ct, totp_key_version: v} = user)
      when is_binary(nonce) and is_binary(ct) do
    with {:ok, secret} <- Encryption.decrypt(nonce, ct, v) do
      maybe_reencrypt_secret(user, secret, v)
      {:ok, secret}
    end
  end

  defp maybe_reencrypt_secret(user, secret, version) do
    if version < Encryption.current_version() do
      {nonce, ciphertext, new_version} = encrypt_secret(secret)
      user
      |> change(%{encrypted_totp_secret: ciphertext, totp_secret_nonce: nonce, totp_key_version: new_version})
      |> Repo.update()
    end
    :ok
  end
```
Delete `decrypt_secret/2`. `disable_totp/1` also resets `totp_key_version: 1`.

`organization.ex` `encrypt_smtp_password/1` and `encrypt_api_key/1`: destructure `{:ok, nonce, ciphertext, version}` and `put_change` the matching `*_key_version`; on `""` clear also resets version to 1.

`organizations.ex` `decrypt_field/3` → `decrypt_field(org, nonce_field, cipher_field, version_field)` and pass the version; after a successful decrypt with `version < Encryption.current_version()`, re-encrypt and `Repo.update_all` the three columns for `org.id` (use `from(o in Organization, where: o.id == ^org.id)`; runs in whatever RLS context the caller has — org settings pages are in org context, `Mailer.deliver_with_org_smtp` too). Update the two public callers to pass `:openrouter_key_version` / `:smtp_key_version`.

- [ ] **Step 6: Run tests, commit**

Run: `mix test test/estimate/encryption_test.exs test/estimate/accounts/ test/estimate_web/live/user_live/ test/estimate_web/live/settings_live/ test/estimate/organizations_mcp_settings_test.exs`
Expected: PASS.

```bash
git add priv/repo/migrations/20260902141000_add_encryption_key_versions.exs lib/estimate/encryption.ex lib/estimate/application.ex config/runtime.exs config/test.exs README.md lib/estimate/accounts/user.ex lib/estimate/accounts/organization.ex lib/estimate/accounts/totp.ex lib/estimate/organizations.ex test/estimate/encryption_test.exs
git commit -m "feat(security): versioned encryption key ring with ENCRYPTION_KEY and lazy re-encryption"
```

---

### Task 3: `mix estimate.rotate_encryption`

**Files:**
- Create: `lib/mix/tasks/estimate.rotate_encryption.ex`
- Test: `test/estimate/encryption_rotation_test.exs` (create)

**Interfaces:**
- Produces: `Estimate.Encryption.Rotation.run() :: %{users: n, organizations: n}` (the logic lives in `lib/estimate/encryption/rotation.ex` so tests call it without Mix); the Mix task calls it and prints counts.

- [ ] **Step 1: Failing test**

```elixir
defmodule Estimate.EncryptionRotationTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.{Encryption, Organizations, Repo}
  alias Estimate.Encryption.Rotation

  @v2 Base.encode64(:crypto.strong_rand_bytes(32))

  setup do
    prev = Application.get_env(:estimate, Estimate.Encryption, [])
    Application.put_env(:estimate, Estimate.Encryption, key: nil)
    Encryption.load_keys()
    on_exit(fn -> Application.put_env(:estimate, Estimate.Encryption, prev); Encryption.load_keys() end)
    :ok
  end

  test "rotates every v1 row to the current key and is idempotent" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    %{organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_smtp_settings(org, %{"smtp_host" => "smtp.example.com", "smtp_from_email" => "a@b.co", "smtp_password" => "pw-secret"})

    Application.put_env(:estimate, Estimate.Encryption, key: @v2)
    Encryption.load_keys()

    assert %{users: 1, organizations: 1} = Rotation.run()
    assert Estimate.Accounts.get_user!(user.id).totp_key_version == 2
    assert Repo.reload!(org).smtp_key_version == 2
    assert {:ok, ^secret} = Estimate.Accounts.Totp.get_decrypted_secret(Estimate.Accounts.get_user!(user.id))
    assert Organizations.get_decrypted_smtp_password(Repo.reload!(org)) == "pw-secret"

    assert %{users: 0, organizations: 0} = Rotation.run()
  end
end
```
Check `Organization.smtp_settings_changeset/2` required fields; supply whatever it requires (read `lib/estimate/accounts/organization.ex`).

- [ ] **Step 2: Run to verify failure** — `mix test test/estimate/encryption_rotation_test.exs` → `Rotation` undefined.

- [ ] **Step 3: Implement**

`lib/estimate/encryption/rotation.ex`:
```elixir
defmodule Estimate.Encryption.Rotation do
  @moduledoc "Eagerly re-encrypts every stored secret that is not on the current key version."
  import Ecto.Query
  alias Estimate.{Encryption, Repo}
  alias Estimate.Accounts.{Organization, User}

  @spec run() :: %{users: non_neg_integer(), organizations: non_neg_integer()}
  def run do
    current = Encryption.current_version()

    Repo.without_rls(fn ->
      users =
        from(u in User, where: not is_nil(u.encrypted_totp_secret) and u.totp_key_version < ^current)
        |> Repo.all()
        |> Enum.count(&rotate_user(&1, current))

      orgs =
        from(o in Organization,
          where:
            (not is_nil(o.encrypted_openrouter_api_key) and o.openrouter_key_version < ^current) or
              (not is_nil(o.encrypted_smtp_password) and o.smtp_key_version < ^current)
        )
        |> Repo.all()
        |> Enum.count(&rotate_org(&1, current))

      %{users: users, organizations: orgs}
    end)
  end

  defp rotate_user(user, current) do
    with {:ok, pt} <- Encryption.decrypt(user.totp_secret_nonce, user.encrypted_totp_secret, user.totp_key_version),
         {:ok, n, ct, ^current} <- Encryption.encrypt(pt),
         {1, _} <- Repo.update_all(from(u in User, where: u.id == ^user.id), set: [encrypted_totp_secret: ct, totp_secret_nonce: n, totp_key_version: current]) do
      true
    else
      _ -> false
    end
  end

  defp rotate_org(org, current) do
    api = rotate_field(org, :openrouter_api_key_nonce, :encrypted_openrouter_api_key, :openrouter_key_version, current)
    smtp = rotate_field(org, :smtp_password_nonce, :encrypted_smtp_password, :smtp_key_version, current)
    api or smtp
  end

  defp rotate_field(org, nonce_f, ct_f, ver_f, current) do
    with ct when is_binary(ct) <- Map.get(org, ct_f),
         true <- Map.get(org, ver_f) < current,
         {:ok, pt} <- Encryption.decrypt(Map.get(org, nonce_f), ct, Map.get(org, ver_f)),
         {:ok, n, new_ct, ^current} <- Encryption.encrypt(pt),
         {1, _} <- Repo.update_all(from(o in Organization, where: o.id == ^org.id), set: [{ct_f, new_ct}, {nonce_f, n}, {ver_f, current}]) do
      true
    else
      _ -> false
    end
  end
end
```

`lib/mix/tasks/estimate.rotate_encryption.ex`:
```elixir
defmodule Mix.Tasks.Estimate.RotateEncryption do
  @moduledoc "Re-encrypts all stored secrets with the current ENCRYPTION_KEY. Idempotent.\n\n    mix estimate.rotate_encryption"
  use Mix.Task
  @shortdoc "Re-encrypt stored secrets with the current key"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    %{users: u, organizations: o} = Estimate.Encryption.Rotation.run()
    Mix.shell().info("Rotated #{u} user secret(s) and #{o} organization(s) to key v#{Estimate.Encryption.current_version()}.")
  end
end
```

- [ ] **Step 4: Run, commit** — `mix test test/estimate/encryption_rotation_test.exs test/estimate/encryption_test.exs`.
```bash
git add lib/estimate/encryption/rotation.ex lib/mix/tasks/estimate.rotate_encryption.ex test/estimate/encryption_rotation_test.exs
git commit -m "feat(security): mix estimate.rotate_encryption re-encrypts secrets eagerly"
```

---

### Task 4: Invite hardening — CSPRNG codes, atomic claim, assignable roles

**Files:**
- Modify: `lib/estimate/accounts/invite.ex`, `lib/estimate/organizations.ex` (`invite_acceptance_multi/2`, `accept_invite/2`, `update_membership_role/2`)
- Test: `test/estimate/organizations/invite_hardening_test.exs` (create)

**Interfaces:**
- `Invite.generate_code/1` uses `:crypto.strong_rand_bytes`.
- `invite_acceptance_multi/2`: the `:verify_still_valid` read + `:invite` update are replaced by one `Ecto.Multi.run(:claim, ...)` that does `update_all` with the validity predicate and returns `{:error, :expired}` unless exactly one row changed. `accept_invite/2` maps `{:error, :claim, :expired, _}` → `{:error, :expired}`; `Accounts.register_user_and_accept_invite/2` keeps returning `{:error, reason}` for that op (check its `case`).
- `Invite.changeset/2` and `code_changeset/2` validate role in `Membership.assignable_roles()`; `Organizations.update_membership_role/2` returns `{:error, :invalid_role}` for anything else.

- [ ] **Step 1: Failing tests**

```elixir
defmodule Estimate.Organizations.InviteHardeningTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures
  alias Estimate.Accounts.Invite
  alias Estimate.Organizations

  test "invite codes use the 32-char alphabet, are 8 long, and 1000 draws do not repeat" do
    codes = for _ <- 1..1000, do: Invite.generate_code()
    assert Enum.all?(codes, &(String.length(&1) == 8 and String.match?(&1, ~r/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$/)))
    assert length(Enum.uniq(codes)) == 1000
  end

  test "an invite cannot be accepted twice: second claim fails with :expired and creates no membership" do
    %{user: owner, organization: org} = user_with_organization_fixture()
    invite = invite_fixture(org, owner, %{"email" => "a@example.com"})
    a = user_fixture(%{email: "a@example.com"})
    assert {:ok, _} = Organizations.accept_invite(invite, a)

    b = user_fixture(%{email: "a@example.com2"})
    # same invite struct (stale, accepted_at still nil in memory) — claim must hit the DB predicate
    invite_stale = %{invite | email: nil}
    assert {:error, :expired} = Organizations.accept_invite(invite_stale, b)
    refute Organizations.get_user_membership(b.id, org.id)
  end

  test "invites cannot carry the owner role" do
    %{user: owner, organization: org} = user_with_organization_fixture()
    assert {:error, cs} = Organizations.create_invite(org.id, %{email: "x@example.com", role: "owner"}, owner.id)
    assert %{role: [_]} = errors_on(cs)
    assert {:error, cs} = Organizations.create_invite_code(org.id, "owner", owner.id)
    assert %{role: [_]} = errors_on(cs)
  end

  test "update_membership_role refuses owner" do
    %{organization: org} = user_with_organization_fixture()
    member = user_fixture()
    m = membership_fixture(member, org, "member")
    assert {:error, :invalid_role} = Organizations.update_membership_role(m, "owner")
    assert Organizations.get_user_membership(member.id, org.id).role == "member"
  end
end
```
Check `invite_fixture/3`'s attrs shape in `accounts_fixtures.ex` (string vs atom keys) and adapt.

- [ ] **Step 2: Run to verify failure** — `mix test test/estimate/organizations/invite_hardening_test.exs`.

- [ ] **Step 3: Implement**

`invite.ex`:
```elixir
  def generate_code(length \\ 8) do
    alphabet = @code_alphabet
    size = length(alphabet)

    :crypto.strong_rand_bytes(length)
    |> :binary.bin_to_list()
    |> Enum.map(&<<Enum.at(alphabet, rem(&1, size))>>)
    |> Enum.join()
  end
```
(32 divides 256 evenly, so `rem/2` is unbiased.) Both changesets: `validate_inclusion(:role, Estimate.Accounts.Membership.assignable_roles())`.

`organizations.ex` `invite_acceptance_multi/2`: replace the `:verify_still_valid` and `:invite` steps with
```elixir
    |> Ecto.Multi.run(:claim, fn repo, _ ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      case repo.update_all(
             from(i in Invite, where: i.id == ^invite.id and is_nil(i.accepted_at) and i.expires_at > ^now),
             set: [accepted_at: now]
           ) do
        {1, _} -> {:ok, :claimed}
        _ -> {:error, :expired}
      end
    end)
```
`accept_invite/2`: replace the `:verify_still_valid` clause with `{:error, :claim, :expired, _} -> {:error, :expired}`. `Accounts.register_user_and_accept_invite/2`: confirm its `case` returns `{:error, reason}` for non-changeset failures of `:claim` (adapt the clause name if it matched `:verify_still_valid`).

`update_membership_role/2`:
```elixir
  def update_membership_role(%Membership{} = membership, role) do
    if role in Membership.assignable_roles() do
      membership |> Membership.changeset(%{role: role}) |> Repo.update()
    else
      {:error, :invalid_role}
    end
  end
```
`Roster.change_member_role/2` already whitelists; add `{:error, :invalid_role} -> put_flash(..., "Invalid role")` to its `case`.

- [ ] **Step 4: Run, commit** — `mix test test/estimate/ test/estimate_web/live/settings_live/ test/estimate_web/live/onboarding_test.exs test/estimate_web/live/organizations_smoke_test.exs`.
```bash
git add lib/estimate/accounts/invite.ex lib/estimate/organizations.ex lib/estimate_web/live/settings_live/members/roster.ex test/estimate/organizations/invite_hardening_test.exs
git commit -m "fix(security): CSPRNG invite codes, atomic invite claim, no owner via invites or role change"
```

---

### Task 5: Ownership transfer, leave organization, pending-only approval, collaborator membership check

**Files:**
- Modify: `lib/estimate/organizations.ex` (`transfer_ownership/3`, `leave_organization/2`, `approve_join_request/2`), `lib/estimate/portfolio.ex` (`add_collaborator/3`)
- Test: `test/estimate/organizations/ownership_test.exs` (create), `test/estimate/accounts_test.exs` (append join-request + collaborator tests)

**Interfaces:**
- `Organizations.transfer_ownership(org_id, actor_user_id, target_user_id) :: {:ok, %{new_owner: %Membership{}, previous_owner: %Membership{}}} | {:error, :not_owner | :not_a_member | :same_user}`.
- `Organizations.leave_organization(user_id, org_id) :: {:ok, %Membership{}} | {:error, :not_a_member | :sole_owner | :sole_project_owner}` — sole owner = the only membership with role owner in the org; sole project owner = `Portfolio.list_sole_owned_projects(user_id, org_id) != []`. Otherwise delegates to `delete_membership/2` with `%{}`.
- `approve_join_request/2` → `{:error, :not_pending}` unless `request.status == "pending"`.
- `Portfolio.add_collaborator/3` → `{:error, :not_a_member}` unless the user has a membership in the project's org.

- [ ] **Step 1: Failing tests**

`test/estimate/organizations/ownership_test.exs`:
```elixir
defmodule Estimate.Organizations.OwnershipTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures}
  alias Estimate.{Organizations, Portfolio}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    %{owner: owner, org: org, member: member}
  end

  test "owner transfers ownership: target becomes owner, actor becomes admin", ctx do
    assert {:ok, %{new_owner: n, previous_owner: p}} = Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, ctx.member.id)
    assert n.role == "owner" and n.user_id == ctx.member.id
    assert p.role == "admin" and p.user_id == ctx.owner.id
    assert Organizations.get_user_membership(ctx.member.id, ctx.org.id).role == "owner"
    assert Organizations.get_user_membership(ctx.owner.id, ctx.org.id).role == "admin"
  end

  test "non-owner cannot transfer; target must be a member; not to self", ctx do
    admin = user_fixture(); _ = membership_fixture(admin, ctx.org, "admin")
    assert {:error, :not_owner} = Organizations.transfer_ownership(ctx.org.id, admin.id, ctx.member.id)
    stranger = user_fixture()
    assert {:error, :not_a_member} = Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, stranger.id)
    assert {:error, :same_user} = Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, ctx.owner.id)
    assert Organizations.get_user_membership(ctx.owner.id, ctx.org.id).role == "owner"
  end

  test "sole owner cannot leave; after transfer they can", ctx do
    assert {:error, :sole_owner} = Organizations.leave_organization(ctx.owner.id, ctx.org.id)
    {:ok, _} = Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, ctx.member.id)
    assert {:ok, _} = Organizations.leave_organization(ctx.owner.id, ctx.org.id)
    refute Organizations.get_user_membership(ctx.owner.id, ctx.org.id)
  end

  test "sole project owner cannot leave", ctx do
    project = project_fixture(nil, ctx.member)
    _ = project
    assert {:error, :sole_project_owner} = Organizations.leave_organization(ctx.member.id, ctx.org.id)
    assert Organizations.get_user_membership(ctx.member.id, ctx.org.id)
  end

  test "member with no sole-owned projects can leave", ctx do
    assert {:ok, _} = Organizations.leave_organization(ctx.member.id, ctx.org.id)
    refute Organizations.get_user_membership(ctx.member.id, ctx.org.id)
  end

  test "non-member cannot leave", ctx do
    stranger = user_fixture()
    assert {:error, :not_a_member} = Organizations.leave_organization(stranger.id, ctx.org.id)
  end
end
```
`project_fixture(nil, member)` creates a project owned by `member` (auto-owner collaborator) in the member's first org — confirm in `portfolio_fixtures.ex` that it picks `member`'s membership org (it uses `Repo.get_by(Membership, user_id:)`; `member` has exactly one membership here).

Append to `accounts_test.exs` "join requests workflow":
```elixir
    test "approve refuses a request that is not pending" do
      %{user: owner, organization: org} = user_with_organization_fixture()
      requester = user_fixture()
      {:ok, jr} = Organizations.create_join_request(requester.id, org.id)
      {:ok, jr} = Organizations.reject_join_request(jr, owner.id)
      assert {:error, :not_pending} = Organizations.approve_join_request(jr, owner.id)
      refute Organizations.get_user_membership(requester.id, org.id)
    end
```
and a new describe:
```elixir
  describe "Portfolio.add_collaborator/3" do
    test "refuses a user who is not a member of the project's org" do
      %{user: owner} = user_with_organization_fixture()
      project = project_fixture(nil, owner)
      stranger = user_fixture()
      assert {:error, :not_a_member} = Portfolio.add_collaborator(project.id, stranger.id, "viewer")
      refute Portfolio.get_collaborator(project.id, stranger.id)
    end
  end
```

- [ ] **Step 2: Run to verify failure** — both files.

- [ ] **Step 3: Implement in `organizations.ex`**

```elixir
  @doc "Owner-only: makes `target_user_id` the owner and demotes the actor to admin, atomically."
  def transfer_ownership(org_id, actor_user_id, target_user_id) do
    cond do
      actor_user_id == target_user_id ->
        {:error, :same_user}

      true ->
        actor = get_user_membership(actor_user_id, org_id)
        target = get_user_membership(target_user_id, org_id)

        cond do
          is_nil(actor) or actor.role != "owner" -> {:error, :not_owner}
          is_nil(target) -> {:error, :not_a_member}
          true -> do_transfer(actor, target)
        end
    end
  end

  defp do_transfer(actor, target) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:new_owner, Membership.changeset(target, %{role: "owner"}))
    |> Ecto.Multi.update(:previous_owner, Membership.changeset(actor, %{role: "admin"}))
    |> Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, _op, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Self-service leave. Refused for the org's only owner and for sole owners of any project."
  def leave_organization(user_id, org_id) do
    case get_user_membership(user_id, org_id) do
      nil ->
        {:error, :not_a_member}

      membership ->
        cond do
          membership.role == "owner" and count_owners(org_id) == 1 -> {:error, :sole_owner}
          Estimate.Portfolio.list_sole_owned_projects(user_id, org_id) != [] -> {:error, :sole_project_owner}
          true -> delete_membership(membership, %{})
        end
    end
  end

  defp count_owners(org_id) do
    from(m in Membership, where: m.organization_id == ^org_id and m.role == "owner")
    |> Repo.aggregate(:count)
  end
```
`Membership.changeset/2` validates `role` against `@roles` (includes owner) — that is the one legitimate path to owner besides creation. `approve_join_request/2`: first line `if request.status != "pending", do: {:error, :not_pending}, else: <existing multi>` (restructure into a private `do_approve/2`).

`portfolio.ex` `add_collaborator/3`:
```elixir
  def add_collaborator(project_id, user_id, role \\ "viewer") do
    Repo.ensure_org_context(fn ->
      org_id = from(p in Project, where: p.id == ^project_id, select: p.organization_id) |> Repo.one()

      member? =
        not is_nil(org_id) and
          Repo.exists?(from(m in Estimate.Accounts.Membership, where: m.user_id == ^user_id and m.organization_id == ^org_id))

      if member? do
        %ProjectCollaborator{}
        |> ProjectCollaborator.changeset(%{project_id: project_id, user_id: user_id, role: role})
        |> Repo.insert()
      else
        {:error, :not_a_member}
      end
    end)
  end
```
Check every caller of `add_collaborator/3` handles a non-changeset error (`grep -rn add_collaborator lib`): `Portfolio.create_project` inserts the owner via Multi (not this function); the collaborators tab LV and `upsert_owner` in `delete_membership` — adapt their `case` clauses to flash/handle `{:error, :not_a_member}` ("Not authorized").

- [ ] **Step 4: Run, commit** — `mix test test/estimate/ test/estimate_web/live/project_live/ test/estimate_web/live/settings_live/`.
```bash
git add lib/estimate/organizations.ex lib/estimate/portfolio.ex lib/estimate_web/live/project_live/ test/estimate/organizations/ownership_test.exs test/estimate/accounts_test.exs
git commit -m "feat(membership): ownership transfer, leave organization, pending-only approval, membership-checked collaborators"
```

---

### Task 6: UI — "Make owner" and "Leave organization"

**Files:**
- Modify: `lib/estimate_web/live/settings_live/members.ex` (assigns/events/modal), `lib/estimate_web/live/settings_live/members/roster.ex`, `lib/estimate_web/live/settings_live/components/member_components.ex`
- Modify: `lib/estimate_web/live/settings_live/index.ex` (Leave card + events)
- Test: `test/estimate_web/live/settings_live/members_test.exs` (append), `test/estimate_web/live/settings_live/leave_org_test.exs` (create)

**Interfaces:**
- Members: events `confirm_transfer_ownership` (`%{"id" => membership_id}`), `cancel_transfer_ownership`, `transfer_ownership`; assign `transferring_to` (membership or nil). Button visible only when `@current_membership.role == "owner"` and the row is another member. Success flash "Ownership transferred"; after transfer the actor is admin, so reload `members` and `current_membership`.
- Settings General: card "Leave organization" (hidden for sole owners, replaced by text "Transfer ownership to another member before leaving." — computed at mount via `Organizations.count_owners/1`, make it public); events `confirm_leave`, `cancel_leave`, `leave_organization`; success → flash "You left the organization" + `push_navigate` to `/organizations`; `:sole_project_owner` → flash "Transfer your projects before leaving."; `:sole_owner` → "Transfer ownership before leaving."

- [ ] **Step 1: Failing tests**

`members_test.exs`, new describe (uses `setup_org`, `add_member/2`, `path_for/1`, `assigns/1`):
```elixir
  describe "transfer ownership" do
    setup :setup_org

    test "owner transfers to a member; roles swap; flash", %{conn: conn, org: org, owner: owner} do
      %{user: member, membership: m} = add_member(org, "member")
      {:ok, lv, _} = live(log_in_user(conn, owner), path_for(org.id))

      render_click(lv, "confirm_transfer_ownership", %{"id" => m.id})
      assert assigns(lv).transferring_to.id == m.id
      html = render_click(lv, "transfer_ownership", %{})
      assert html =~ "Ownership transferred"
      assert Organizations.get_user_membership(member.id, org.id).role == "owner"
      assert Organizations.get_user_membership(owner.id, org.id).role == "admin"
      assert assigns(lv).current_membership.role == "admin"
    end

    test "admin cannot transfer ownership", %{conn: conn, org: org} do
      %{user: admin} = add_member(org, "admin")
      %{membership: m} = add_member(org, "member")
      {:ok, lv, _} = live(log_in_user(conn, admin), path_for(org.id))
      render_click(lv, "confirm_transfer_ownership", %{"id" => m.id})
      assert assigns(lv).transferring_to == nil
      html = render_click(lv, "transfer_ownership", %{})
      assert html =~ "Not authorized"
      assert Organizations.get_user_membership(m.user_id, org.id).role == "member"
    end
  end
```

`leave_org_test.exs`:
```elixir
defmodule EstimateWeb.SettingsLive.LeaveOrgTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures}
  alias Estimate.Organizations

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    %{owner: owner, org: org, member: member}
  end

  test "sole owner sees the transfer-first text and cannot leave", %{conn: conn, owner: owner, org: org} do
    {:ok, lv, html} = live(log_in_user(conn, owner), ~p"/org/#{org.id}/settings")
    assert html =~ "Transfer ownership to another member before leaving."
    refute html =~ ~s(phx-click="confirm_leave")
    render_click(lv, "confirm_leave", %{})
    html = render_click(lv, "leave_organization", %{})
    assert html =~ "Transfer ownership before leaving."
    assert Organizations.get_user_membership(owner.id, org.id)
  end

  test "member leaves and is redirected", %{conn: conn, member: member, org: org} do
    {:ok, lv, _} = live(log_in_user(conn, member), ~p"/org/#{org.id}/settings")
    render_click(lv, "confirm_leave", %{})
    assert assigns(lv).leaving == true
    assert {:error, {:live_redirect, %{to: "/organizations"}}} = render_click(lv, "leave_organization", %{})
    refute Organizations.get_user_membership(member.id, org.id)
  end

  test "sole project owner is refused", %{conn: conn, member: member, org: org} do
    _project = project_fixture(nil, member)
    {:ok, lv, _} = live(log_in_user(conn, member), ~p"/org/#{org.id}/settings")
    render_click(lv, "confirm_leave", %{})
    html = render_click(lv, "leave_organization", %{})
    assert html =~ "Transfer your projects before leaving."
    assert Organizations.get_user_membership(member.id, org.id)
  end
end
```
If `render_click` on a redirecting event returns differently in this LiveView version, use `assert_redirect(lv, "/organizations")` after the click.

- [ ] **Step 2: Run to verify failure** — both files.

- [ ] **Step 3: Implement**

`roster.ex`:
```elixir
  def confirm_transfer_ownership(socket, %{"id" => id}) do
    require_owner(socket, fn ->
      case Enum.find(socket.assigns.members, &(&1.id == id and &1.user_id != socket.assigns.current_user.id)) do
        nil -> {:noreply, put_flash(socket, :error, "Member not found")}
        m -> {:noreply, assign(socket, :transferring_to, m)}
      end
    end)
  end

  def cancel_transfer_ownership(socket, _), do: {:noreply, assign(socket, :transferring_to, nil)}

  def transfer_ownership(socket, _params) do
    require_owner(socket, fn ->
      case socket.assigns.transferring_to do
        nil ->
          {:noreply, socket}

        target ->
          case Organizations.transfer_ownership(socket.assigns.org_id, socket.assigns.current_user.id, target.user_id) do
            {:ok, %{previous_owner: me}} ->
              {:noreply,
               socket
               |> put_flash(:info, "Ownership transferred")
               |> assign(:transferring_to, nil)
               |> assign(:current_membership, me)
               |> assign(:is_admin, true)
               |> assign(:members, Organizations.list_organization_members(socket.assigns.org_id))}

            {:error, _} ->
              {:noreply, socket |> put_flash(:error, "Could not transfer ownership") |> assign(:transferring_to, nil)}
          end
      end
    end)
  end

  defp require_owner(socket, fun) do
    if socket.assigns.current_membership.role == "owner",
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "Not authorized")}
  end
```
`members.ex`: assign `transferring_to: nil` at mount; dispatch the three events; add a `<.confirm_modal :if={@transferring_to} id="transfer-ownership-modal" title="Transfer ownership" message={"#{@transferring_to.user.name || @transferring_to.user.email} will become the owner and you will become an admin."} confirm_text="Transfer" confirm_event="transfer_ownership" cancel_event="cancel_transfer_ownership" />`. `member_components.ex` row actions: inside the existing admin branch add
```heex
            <button
              :if={@current_membership.role == "owner"}
              phx-click="confirm_transfer_ownership"
              phx-value-id={membership.id}
              title="Make owner"
              aria-label="Make owner"
              class="text-base-content/40 hover:text-base-content/70 transition-colors"
            >
              <.icon name="hero-key" class="w-4 h-4" />
            </button>
```

`settings_live/index.ex`: mount assigns `leaving: false`, `sole_owner: socket.assigns.current_membership.role == "owner" and Organizations.count_owners(org.id) == 1`; card after Security:
```heex
        <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden" id="leave-org">
          <div class="p-6">
            <h2 class="text-xl font-semibold text-base-content">Leave organization</h2>
            <p :if={@sole_owner} class="mt-1 text-sm text-base-content/60">
              Transfer ownership to another member before leaving.
            </p>
            <p :if={!@sole_owner} class="mt-1 text-sm text-base-content/60">
              You will lose access to this organization's data immediately.
            </p>
            <button
              :if={!@sole_owner}
              phx-click="confirm_leave"
              class="mt-4 px-4 py-1.5 text-sm font-medium text-error border border-error/30 rounded-md hover:bg-error/10 transition-colors"
            >
              Leave organization
            </button>
          </div>
        </div>
        <.confirm_modal :if={@leaving} id="leave-org-modal" title="Leave organization?" message="You will lose access immediately." confirm_text="Leave" confirm_event="leave_organization" cancel_event="cancel_leave" />
```
Events:
```elixir
  def handle_event("confirm_leave", _, socket), do: {:noreply, assign(socket, :leaving, true)}
  def handle_event("cancel_leave", _, socket), do: {:noreply, assign(socket, :leaving, false)}

  def handle_event("leave_organization", _, socket) do
    case Organizations.leave_organization(socket.assigns.current_user.id, socket.assigns.org_id) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "You left the organization") |> push_navigate(to: ~p"/organizations")}
      {:error, :sole_owner} -> {:noreply, socket |> put_flash(:error, "Transfer ownership before leaving.") |> assign(:leaving, false)}
      {:error, :sole_project_owner} -> {:noreply, socket |> put_flash(:error, "Transfer your projects before leaving.") |> assign(:leaving, false)}
      {:error, _} -> {:noreply, socket |> put_flash(:error, "Could not leave organization") |> assign(:leaving, false)}
    end
  end
```
Make `Organizations.count_owners/1` public (`def`).

- [ ] **Step 4: Run, commit** — `mix test test/estimate_web/live/settings_live/`.
```bash
git add lib/estimate_web/live/settings_live/ test/estimate_web/live/settings_live/
git commit -m "feat(members): make-owner action and leave-organization card"
```

---

### Task 7: Full verification

- [ ] `mix precommit` green (compile no warnings, unused deps, format, full suite).
- [ ] Confirm new test files exist and pass: `totp_test.exs`, `encryption_test.exs`, `encryption_rotation_test.exs`, `invite_hardening_test.exs`, `ownership_test.exs`, `leave_org_test.exs`, members_test transfer describe.
- [ ] Commit formatter output if any: `git add -A && git commit -m "chore: format" || true`.
