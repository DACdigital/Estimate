# Audit Batch 3A — Small Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the four small follow-ups carried from audit batches 2a/2b: a version guard in encryption rotation, a race-free changeset path for auto-setting the current estimation, orphan `oauth_clients` pruning in the OAuth janitor, and a consent screen that demotes the attacker-chosen client name.

**Architecture:** Four independent, additive changes in existing modules. No migrations, no new processes, no template restructuring beyond one HEEx file. Each task is TDD: failing test → minimal code → green → commit.

**Tech Stack:** Elixir 1.18, Phoenix 1.8.3, Ecto 3.13 / Postgres 17 (RLS), ExUnit with `Estimate.DataCase` / `EstimateWeb.ConnCase` (SQL sandbox).

**Spec:** `docs/superpowers/specs/2026-09-16-audit-batch-3-followups-decomposition-perf-design.md` — section "3A — small follow-ups" (A1–A4). Read it first.

## Global Constraints

- Tests never use `Process.sleep` (AGENTS.md). Diverge state from its default before asserting a change.
- `mix precommit` (format, `--warnings-as-errors`, full test suite) must be green before every commit.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- No schema/migration changes. No changes to `Calculator`, MCP tools, CSP.
- Work on the batch branch (`audit/batch-3a`), based on local `main` (`git reset --hard main` after creating the worktree — the worktree tool bases on stale `origin/main`).
- 1Password SSH signing may lock: if `git commit` fails with "failed to fill whole buffer", stop and report; do not retry in a loop.

---

### Task 1: Rotation version guard (A1)

**Files:**
- Modify: `lib/estimate/encryption/rotation.ex`
- Test: `test/estimate/encryption_rotation_test.exs`

**Interfaces:**
- Consumes: `Estimate.Encryption.encrypt/1 :: {:ok, nonce, ct, version}`, `Estimate.Encryption.decrypt/3`, `Estimate.Encryption.current_version/0`.
- Produces: `Rotation.rotate_user/2` and `Rotation.rotate_org/2` become public (`@doc false`) returning `:ok | :unchanged | :failed`; `Rotation.run/0` result map unchanged.

Background: `rotate_user/2` and `rotate_field/5` `update_all` the row unconditionally. If the lazy read-path (`Encryption`-aware getters in `Accounts.Totp` / `Organizations`) already re-encrypted the row to the current version between the `Repo.all` and the `update_all`, the eager pass overwrites it with a second, equivalent ciphertext — a wasted write, and a real race if the secret itself changed meanwhile. Guard the update on the version we read.

- [ ] **Step 1: Write the failing tests**

Append inside the module in `test/estimate/encryption_rotation_test.exs` (before the final `end`):

```elixir
  describe "version guard" do
    test "a user row already rotated by the lazy read-path is left untouched and reported unchanged" do
      %{user: user} = user_with_totp_fixture()
      stale = Repo.get!(User, user.id)
      assert stale.totp_key_version == 1

      Application.put_env(:estimate, Estimate.Encryption, key: @v2)
      Encryption.load_keys()

      # Simulate the read path having re-encrypted the row to v2 already.
      {:ok, pt} = Encryption.decrypt(stale.totp_secret_nonce, stale.encrypted_totp_secret, 1)
      {:ok, n2, ct2, 2} = Encryption.encrypt(pt)

      {1, _} =
        Repo.update_all(from(u in User, where: u.id == ^user.id),
          set: [encrypted_totp_secret: ct2, totp_secret_nonce: n2, totp_key_version: 2]
        )

      assert Rotation.rotate_user(stale, 2) == :unchanged

      fresh = Repo.get!(User, user.id)
      assert fresh.encrypted_totp_secret == ct2
      assert fresh.totp_secret_nonce == n2
      assert fresh.totp_key_version == 2
    end

    test "an organization row already rotated by the lazy read-path is left untouched and reported unchanged" do
      %{organization: org} = user_with_organization_fixture()

      {:ok, org} =
        Organizations.update_smtp_settings(org, %{
          "smtp_host" => "smtp.example.com",
          "smtp_from_email" => "a@b.co",
          "smtp_password" => "pw-secret"
        })

      stale = Repo.reload!(org)
      assert stale.smtp_key_version == 1

      Application.put_env(:estimate, Estimate.Encryption, key: @v2)
      Encryption.load_keys()

      {:ok, pt} =
        Encryption.decrypt(stale.smtp_password_nonce, stale.encrypted_smtp_password, 1)

      {:ok, n2, ct2, 2} = Encryption.encrypt(pt)

      {1, _} =
        Repo.update_all(from(o in Estimate.Accounts.Organization, where: o.id == ^org.id),
          set: [encrypted_smtp_password: ct2, smtp_password_nonce: n2, smtp_key_version: 2]
        )

      assert Rotation.rotate_org(stale, 2) == :unchanged

      fresh = Repo.reload!(org)
      assert fresh.encrypted_smtp_password == ct2
      assert fresh.smtp_password_nonce == n2
      assert fresh.smtp_key_version == 2
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/estimate/encryption_rotation_test.exs`
Expected: 2 failures — `Rotation.rotate_user/2` / `rotate_org/2` are undefined (private).

- [ ] **Step 3: Implement the guard**

In `lib/estimate/encryption/rotation.ex`:

1. In `run/0`, the users reduce must accept `:unchanged`:

```elixir
      |> Enum.reduce({0, 0}, fn user, {ok, failed} ->
        case rotate_user(user, current) do
          :ok -> {ok + 1, failed}
          :failed -> {ok, failed + 1}
          :unchanged -> {ok, failed}
        end
      end)
```

2. Replace `defp rotate_user/2` with a public, guarded version:

```elixir
  # Public for tests only. Returns :ok (rotated), :unchanged (the row was
  # already moved off `user.totp_key_version` by the lazy read-path between
  # our SELECT and this UPDATE — the WHERE on the version we read makes that
  # a 0-row update instead of an overwrite), or :failed (logged).
  @doc false
  def rotate_user(user, current) do
    old_version = user.totp_key_version

    with {:ok, pt} <-
           Encryption.decrypt(user.totp_secret_nonce, user.encrypted_totp_secret, old_version),
         {:ok, n, ct, ^current} <- Encryption.encrypt(pt),
         {rows, _} when rows in [0, 1] <-
           Repo.update_all(
             from(u in User, where: u.id == ^user.id and u.totp_key_version == ^old_version),
             set: [encrypted_totp_secret: ct, totp_secret_nonce: n, totp_key_version: current]
           ) do
      if rows == 1, do: :ok, else: :unchanged
    else
      reason ->
        Logger.error("rotate: could not re-encrypt users #{user.id}: #{inspect(reason)}")
        :failed
    end
  end
```

3. Make `rotate_org/2` public (`@doc false` + `def`), body unchanged.

4. Replace `rotate_field/5` with the guarded version:

```elixir
  # Returns :ok (rotated), :unchanged (nothing stored on that field, already
  # on the current version, or the row was moved off the version we read by
  # the lazy read-path — the WHERE on `ver_f` turns that race into a 0-row
  # update), or :failed (logged, reason from the `with` else).
  defp rotate_field(org, nonce_f, ct_f, ver_f, current) do
    old_version = Map.get(org, ver_f)

    with ct when is_binary(ct) <- Map.get(org, ct_f),
         true <- old_version < current,
         {:ok, pt} <- Encryption.decrypt(Map.get(org, nonce_f), ct, old_version),
         {:ok, n, new_ct, ^current} <- Encryption.encrypt(pt),
         {rows, _} when rows in [0, 1] <-
           Repo.update_all(
             from(o in Organization,
               where: o.id == ^org.id and field(o, ^ver_f) == ^old_version
             ),
             set: [{ct_f, new_ct}, {nonce_f, n}, {ver_f, current}]
           ) do
      if rows == 1, do: :ok, else: :unchanged
    else
      nil ->
        :unchanged

      false ->
        :unchanged

      reason ->
        Logger.error("rotate: could not re-encrypt organizations #{org.id}: #{inspect(reason)}")
        :failed
    end
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/estimate/encryption_rotation_test.exs`
Expected: all pass (2 existing + 2 new).

- [ ] **Step 5: Precommit and commit**

Run: `mix precommit`
Expected: green.

```bash
git add lib/estimate/encryption/rotation.ex test/estimate/encryption_rotation_test.exs
git commit -m "fix(encryption): guard eager rotation on the key version read

rotate_user/rotate_field now UPDATE ... WHERE key_version = <version we
read>; a row the lazy read-path already re-encrypted is a 0-row update
reported :unchanged, not an overwrite.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Race-free `maybe_auto_set_current/1` via changeset + project lock (A2)

**Files:**
- Modify: `lib/estimate/estimation_engine/estimation.ex`
- Modify: `lib/estimate/estimation_engine/estimations.ex` (`restore_estimation/1` ~line 184, `maybe_auto_set_current/1` ~line 272)
- Test: `test/estimate/estimation_engine/estimations_current_test.exs`

**Interfaces:**
- Produces: `Estimation.set_current_changeset/1 :: Ecto.Changeset.t()`; `Estimations.maybe_auto_set_current/1 :: {:ok, %Estimation{}} | {:ok, :unchanged} | {:error, Ecto.Changeset.t()}` (stays private; exercised through `EstimationEngine.restore_estimation/1`).
- Consumes: `Estimate.Portfolio.Project` schema, `EstimationEngine.soft_delete_estimation/1`, `EstimationEngine.restore_estimation/1`, fixtures `project_fixture/3`, `estimation_fixture/2`.

Background: `restore_estimation/1` runs `maybe_auto_set_current/1` inside an `Ecto.Multi` and discards its result. The function updates with a raw `Ecto.Changeset.change/2`, so a unique-index hit raises `Postgrex.Error`. Inside a transaction a unique violation aborts the Postgres transaction regardless of how Ecto reports it, so the fix is to make the race impossible (lock the project row) and to surface real failures.

- [ ] **Step 1: Write the failing tests**

Replace the whole file `test/estimate/estimation_engine/estimations_current_test.exs` with:

```elixir
defmodule Estimate.EstimationEngine.EstimationsCurrentTest do
  use Estimate.DataCase, async: true
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Estimation
  alias Estimate.Repo

  setup do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    %{project: project}
  end

  test "a second current estimation on one project is a changeset error", %{project: project} do
    first = estimation_fixture(project)
    assert Repo.reload!(first).is_current
    second = estimation_fixture(project)
    refute Repo.reload!(second).is_current

    assert {:error, cs} = second |> Estimation.changeset(%{is_current: true}) |> Repo.update()
    assert %{is_current: ["another estimation is already current"]} = errors_on(cs)
  end

  test "set_current_changeset/1 hits the same unique constraint as a changeset error, not a raise",
       %{project: project} do
    _first = estimation_fixture(project)
    second = estimation_fixture(project)

    assert {:error, cs} = second |> Estimation.set_current_changeset() |> Repo.update()
    assert %{is_current: ["another estimation is already current"]} = errors_on(cs)
    refute Repo.reload!(second).is_current
  end

  test "restoring the only estimation of a project makes it current again", %{project: project} do
    only = estimation_fixture(project)
    assert Repo.reload!(only).is_current

    {:ok, deleted} = EstimationEngine.soft_delete_estimation(Repo.reload!(only))
    refute deleted.is_current

    assert {:ok, restored} = EstimationEngine.restore_estimation(deleted)
    assert Repo.reload!(restored).is_current
  end

  test "restoring when another estimation is current leaves both flags unchanged", %{
    project: project
  } do
    first = estimation_fixture(project)
    second = estimation_fixture(project)
    assert Repo.reload!(first).is_current
    refute Repo.reload!(second).is_current

    {:ok, deleted} = EstimationEngine.soft_delete_estimation(Repo.reload!(second))
    assert {:ok, _restored} = EstimationEngine.restore_estimation(deleted)

    assert Repo.reload!(first).is_current
    refute Repo.reload!(second).is_current
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/estimate/estimation_engine/estimations_current_test.exs`
Expected: `set_current_changeset/1` undefined → 1 failure (compile error for that test); the two restore tests should pass already (they characterize current behaviour) — if either fails, stop and report before changing code.

- [ ] **Step 3: Add `set_current_changeset/1` and share the constraint options**

In `lib/estimate/estimation_engine/estimation.ex` replace `changeset/2` and add the new function:

```elixir
  def changeset(estimation, attrs) do
    estimation
    |> cast(attrs, [:name, :description, :currency_id, :project_id, :is_current])
    |> validate_required([:name, :project_id])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:currency_id)
    |> unique_current_constraint()
  end

  @doc "Marks the estimation current. Carries the partial unique index as a changeset error."
  def set_current_changeset(estimation) do
    estimation
    |> change(is_current: true)
    |> unique_current_constraint()
  end

  # `estimations_unique_current_per_project` is a partial unique index on
  # (project_id) WHERE is_current AND deleted_at IS NULL (migration
  # 20260319080827). One home for its name + message.
  defp unique_current_constraint(changeset) do
    unique_constraint(changeset, :is_current,
      name: :estimations_unique_current_per_project,
      message: "another estimation is already current"
    )
  end
```

- [ ] **Step 4: Lock the project row and surface the result in `restore_estimation/1`**

In `lib/estimate/estimation_engine/estimations.ex`:

1. Add `alias Estimate.Portfolio.Project` next to the existing aliases at the top of the module.

2. Replace `maybe_auto_set_current/1`:

```elixir
  # Called inside restore_estimation/1's transaction. Locks the project row
  # first so two concurrent restores (or a restore racing a create) on the
  # same project serialise here instead of both passing the exists-check and
  # one of them hitting the partial unique index — which, inside a
  # transaction, would abort the whole transaction no matter how Ecto reports
  # it. The changeset still carries the constraint as defense in depth.
  defp maybe_auto_set_current(%Estimation{} = estimation) do
    _locked =
      Repo.one!(
        from(p in Project, where: p.id == ^estimation.project_id, lock: "FOR UPDATE")
      )

    has_current =
      from(e in Estimation,
        where:
          e.project_id == ^estimation.project_id and
            e.is_current == true and
            is_nil(e.deleted_at)
      )
      |> Repo.exists?()

    if has_current do
      {:ok, :unchanged}
    else
      Repo.update(Estimation.set_current_changeset(estimation))
    end
  end
```

3. In `restore_estimation/1` replace the `Multi.run` step so the result is used:

```elixir
      |> Ecto.Multi.run(:auto_current, fn _repo, %{restore: restored} ->
        maybe_auto_set_current(restored)
      end)
```

The existing `case` already maps `{:error, _op, changeset, _}` to `{:error, changeset}`, so a genuine failure now rolls the restore back and surfaces the changeset.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/estimate/estimation_engine/estimations_current_test.exs test/estimate_web/live/project_live/show_test.exs`
Expected: all pass (the show tests cover the restore flow end to end).

- [ ] **Step 6: Precommit and commit**

Run: `mix precommit`
Expected: green.

```bash
git add lib/estimate/estimation_engine/estimation.ex lib/estimate/estimation_engine/estimations.ex test/estimate/estimation_engine/estimations_current_test.exs
git commit -m "fix(estimations): race-free auto-current on restore via project lock + changeset

maybe_auto_set_current locks the project row FOR UPDATE before the
exists-check and updates through Estimation.set_current_changeset/1
(carries the partial unique index as a changeset error). restore_estimation
now uses its result, so a real failure rolls back instead of being swallowed.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Janitor prunes orphan `oauth_clients` (A3)

**Files:**
- Modify: `lib/estimate/mcp/oauth/janitor.ex`
- Test: `test/estimate/mcp/oauth_janitor_test.exs`

**Interfaces:**
- Produces: `Janitor.run/0 :: %{codes: n, tokens: n, clients: n}`.
- Consumes: `Estimate.MCP.OAuth.Client` schema (`inserted_at :utc_datetime`), `Code.client_id`, `Token.client_id`; test helpers `mint/1`, `ago/1` already in the test file; `OAuth.register_client/1`, `OAuth.refresh_tokens/2`.

Background: dynamic client registration inserts one `oauth_clients` row per connector attempt; nothing deletes them. Lifecycle rule (spec A3): a client is pruned when no `oauth_codes` and no `oauth_tokens` row references it **and** it is older than 24h. Tokens/codes are pruned first under their own grace windows, so the client's life is derived from its children; a live grant can never be touched because its token row blocks the delete.

- [ ] **Step 1: Write the failing tests**

In `test/estimate/mcp/oauth_janitor_test.exs`:

1. Change the alias line to include `Client`:

```elixir
  alias Estimate.MCP.OAuth.{Client, Code, Janitor, Token}
```

2. Add a helper below `ago/1`:

```elixir
  defp hours_ago(hours),
    do: DateTime.utc_now() |> DateTime.add(-hours, :hour) |> DateTime.truncate(:second)

  defp age_client(client, inserted_at) do
    {1, _} =
      Repo.update_all(from(c in Client, where: c.id == ^client.id), set: [inserted_at: inserted_at])

    :ok
  end
```

3. Update the first test's assertion so it still matches the wider map — change

```elixir
    assert %{codes: codes, tokens: 1} = Janitor.run()
```

to

```elixir
    assert %{codes: codes, tokens: 1, clients: 0} = Janitor.run()
```

(the setup client is minutes old, so it is kept.)

4. Append these tests before the `"a raising run_fun never crashes..."` test:

```elixir
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/estimate/mcp/oauth_janitor_test.exs`
Expected: the `clients:` key is missing from the run result → the amended first test and the five new tests fail with `MatchError`.

- [ ] **Step 3: Implement the third pruning step**

In `lib/estimate/mcp/oauth/janitor.ex`:

1. Alias `Client`:

```elixir
  alias Estimate.MCP.OAuth.{Client, Code, Token}
```

2. Add the grace constant under the other two:

```elixir
  @client_grace_seconds 24 * 3600
```

3. Update the moduledoc's first paragraph:

```elixir
  @moduledoc """
  Hourly cleanup of OAuth rows that can no longer be used: authorization
  codes more than an hour past expiry that no token references, tokens
  revoked or refresh-expired more than seven days ago, and dynamically
  registered clients older than 24 hours that no code or token references
  any more (a client's life is derived from its children; a live grant's
  token row always blocks the delete). Runs at boot and then every
  `interval_ms`. Disabled in test (config `enabled: false`); `run/0` is
  callable directly.
  """
```

4. Update the log line in `handle_info(:run, state)`:

```elixir
      Logger.info(
        "oauth janitor: pruned #{counts.codes} codes, #{counts.tokens} tokens, #{counts.clients} clients"
      )
```

5. Update the `@spec` and the body of `run/0` — after the codes delete and before the result map:

```elixir
  @spec run() :: %{codes: non_neg_integer(), tokens: non_neg_integer(), clients: non_neg_integer()}
  def run do
    Repo.without_rls(fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      code_cutoff = DateTime.add(now, -@code_grace_seconds)
      token_cutoff = DateTime.add(now, -@token_grace_seconds)
      client_cutoff = DateTime.add(now, -@client_grace_seconds)

      # (the existing `{tokens, _} = Repo.delete_all(...)` and
      #  `{codes, _} = Repo.delete_all(...)` blocks stay exactly as they are here)

      # Clients last: after the two deletes above, any client with no code
      # and no token row is an orphan. The 24h grace protects an in-flight
      # register -> authorize flow that has not minted a code yet. The FK
      # cascade (codes/tokens -> clients, on_delete: :delete_all) is never
      # reached because a referenced client is excluded here.
      has_code = from(c in Code, where: c.client_id == parent_as(:client).id)
      has_token = from(t in Token, where: t.client_id == parent_as(:client).id)

      {clients, _} =
        Repo.delete_all(
          from(cl in Client,
            as: :client,
            where:
              cl.inserted_at < ^client_cutoff and not exists(has_code) and not exists(has_token)
          )
        )

      %{codes: codes, tokens: tokens, clients: clients}
    end)
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/estimate/mcp/oauth_janitor_test.exs`
Expected: all pass.

- [ ] **Step 5: Update the README janitor line**

In `README.md`, find the `OAUTH_JANITOR_INTERVAL_MS` row in the configuration table and change its description to:

```
| `OAUTH_JANITOR_INTERVAL_MS` | prod | no | Sweep interval (ms) for `Estimate.MCP.OAuth.Janitor` (expired codes, dead tokens, and orphan dynamically-registered clients older than 24h); default `3600000` (1 hour) |
```

- [ ] **Step 6: Precommit and commit**

Run: `mix precommit`
Expected: green.

```bash
git add lib/estimate/mcp/oauth/janitor.ex test/estimate/mcp/oauth_janitor_test.exs README.md
git commit -m "feat(oauth): janitor prunes orphan dynamically-registered clients

After tokens and codes, delete oauth_clients older than 24h that no code
or token references. Lifecycle derives from children; a live grant's token
row always blocks the delete. run/0 reports clients: count.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Consent screen demotes the client name (A4)

**Files:**
- Modify: `lib/estimate_web/controllers/oauth_authorize_html/consent.html.heex` (lines 1–6)
- Test: `test/estimate_web/controllers/oauth_authorize_test.exs`

**Interfaces:**
- Consumes: assigns `@client` (`%Client{name: String.t()}`), `@redirect_host` (validated host string) from `OAuthAuthorizeController` (unchanged).

Background: the headline is `Connect {@client.name}` — attacker-chosen text in the most prominent spot. The redirect host is validated against the registered redirect URIs and is the only identity we can vouch for. Make the host the anchor and label the name as self-declared.

- [ ] **Step 1: Write the failing tests**

In `test/estimate_web/controllers/oauth_authorize_test.exs`, replace the test `"consent page shows client, redirect host and org picker"` with:

```elixir
  test "consent page anchors on the redirect host and labels the client name as self-declared",
       %{conn: conn, client: client, org: org} do
    html = conn |> get(~p"/oauth/authorize?#{authorize_params(client)}") |> html_response(200)

    assert html =~ ~r|<h1[^>]*>\s*Connect to claude\.ai\s*</h1>|
    assert html =~ "An app calling itself"
    assert html =~ "“Claude”"
    assert html =~ org.name
    refute html =~ ~r|<h1[^>]*>\s*Connect Claude\s*</h1>|
  end

  test "consent page renders a hostile client name escaped, never as markup", %{conn: conn} do
    {:ok, evil} =
      OAuth.register_client(%{
        "client_name" => "<b onmouseover=alert(1)>claude.ai</b>",
        "redirect_uris" => [@redirect]
      })

    html = conn |> get(~p"/oauth/authorize?#{authorize_params(evil)}") |> html_response(200)

    assert html =~ "&lt;b onmouseover=alert(1)&gt;claude.ai&lt;/b&gt;"
    refute html =~ "<b onmouseover=alert(1)>"
    assert html =~ ~r|<h1[^>]*>\s*Connect to claude\.ai\s*</h1>|
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/estimate_web/controllers/oauth_authorize_test.exs`
Expected: the first new test fails (`Connect to claude.ai` absent, `calling itself` absent); the second fails on the `h1` assertion. Everything else passes.

- [ ] **Step 3: Rewrite the consent header**

Replace lines 1–6 of `lib/estimate_web/controllers/oauth_authorize_html/consent.html.heex` (the `h1` and the first `<p>`) with:

```heex
<div class="max-w-md mx-auto">
  <h1 class="text-xl font-semibold text-base-content mb-1">Connect to {@redirect_host}</h1>
  <p class="text-sm text-base-content/60 mb-3">
    An app calling itself
    <span class="inline-block max-w-[14rem] truncate align-bottom text-base-content/80">“{@client.name}”</span>
    at <span class="font-mono text-base-content">{@redirect_host}</span>
    is asking to access your estimation data, acting as you:
  </p>
```

Everything from `<ul class="mb-4 ...">` down is unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/estimate_web/controllers/oauth_authorize_test.exs test/estimate_web/csp_routes_test.exs`
Expected: all pass (no inline script or style was added, CSP untouched).

- [ ] **Step 5: Precommit and commit**

Run: `mix precommit`
Expected: green.

```bash
git add lib/estimate_web/controllers/oauth_authorize_html/consent.html.heex test/estimate_web/controllers/oauth_authorize_test.exs
git commit -m "fix(oauth): consent screen anchors on the validated redirect host

Headline is 'Connect to <host>'; the attacker-chosen client_name is shown
as 'an app calling itself \"...\"' with CSS truncation so it cannot push
the host off-screen. HEEx escaping covered markup already; tests pin it.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Done criteria

- Four commits on `audit/batch-3a`, each with `mix precommit` green.
- `Rotation.run/0` result map unchanged; `Janitor.run/0` returns `clients:`; `restore_estimation/1` surfaces auto-current failures; consent `h1` is `Connect to <host>`.
- No migration, no new env var, README janitor row updated.

## Unresolved questions

None.
