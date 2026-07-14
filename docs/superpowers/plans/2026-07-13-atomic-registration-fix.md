# Auth — Atomic Registration Fix (invite-code · invite-link · join-request)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Before writing Ecto/Multi code invoke `elixir-phoenix-guide:ecto-nested-associations` and `:ecto-changeset-patterns`; before `_test.exs` invoke `:testing-essentials`. Steps use checkbox (`- [ ]`).

**Goal:** Fix the non-atomic "register then join" bug at all THREE call sites — `registration.ex` invite-code path, `invite_live/accept.ex` register-and-accept, `join_request/new.ex` register-and-request-join — so a failed invite/join no longer leaves an orphaned user row. Do it DRY via one shared invite-acceptance `Ecto.Multi`.

**Architecture:** Extract `Organizations.invite_acceptance_multi/2` (unexecuted `Ecto.Multi` with the validity/email/verify/invite-update/membership-insert steps); make `accept_invite/2` a thin wrapper around it (behavior-preserving — pinned by the merged !3 tests). Add `Accounts.register_user_and_accept_invite/2` and `Accounts.register_user_and_request_join/2` that `Ecto.Multi.merge` the invite/join steps after the `:user` insert, mirroring the existing atomic `register_user_with_organization/2`. Then wire the 3 LiveViews and flip the characterization test from "orphan persists" to "rolled back".

**Tech Stack:** Elixir ~> 1.15, Ecto.Multi, Phoenix.LiveView 1.1.

## Global Constraints
- **Behavior change is scoped to the bug:** a failed invite/join during registration now rolls back the user (was: user persisted). `accept_invite/2`'s existing external behavior (existing-user invite acceptance, `:email_mismatch`/`:expired`/success) is PRESERVED — the !3 characterization + `accounts_test.exs` invite tests must stay green.
- **No DB schema/migration changes** (Multi wraps existing tables/changesets; DB-neutral). Context function signatures may change (approved).
- Gate: `mix compile --warnings-as-errors` clean; full suite green (with the updated/added tests).
- Branch `refactor/auth-finalize`, off merged master.

---

### Task 1: Extract `invite_acceptance_multi` + rewrap `accept_invite/2`

**Files:** Modify `lib/estimate/organizations.ex`. Test: `test/estimate/accounts_test.exs` (existing invite tests must still pass; add one if a gap).

**Interfaces (produced):**
- `Organizations.invite_acceptance_multi(%Invite{}, user_getter) :: Ecto.Multi.t()` — appends steps `:check_invite` (validity + email match via `user_getter.(changes)`), `:verify_still_valid`, `:invite` (accept_changeset), `:membership`. `user_getter` is `(changes_map -> %{id, email})` so callers can supply an existing user (`fn _ -> user end`) or one produced by a prior `:user` step (`fn %{user: u} -> u end`).
- `accept_invite/2` — unchanged signature/return (`{:ok, result} | {:error, :expired | :email_mismatch | changeset}`), now implemented via the multi.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:ecto-nested-associations` + `:ecto-changeset-patterns`.
- [ ] **Step 1:** Add the shared builder (private impl + public wrapper). Move `accept_invite/2`'s pre-multi validity/email `cond` INTO a `:check_invite` `Ecto.Multi.run` step (so it composes in the register flow where the user doesn't exist until `:user` runs):
```elixir
  @doc "Composable Ecto.Multi steps for accepting an invite; user resolved via `user_getter`."
  def invite_acceptance_multi(%Invite{} = invite, user_getter) when is_function(user_getter, 1) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:check_invite, fn _repo, changes ->
      user = user_getter.(changes)

      cond do
        not Invite.valid?(invite) -> {:error, :expired}
        invite.email != nil and invite.email != user.email -> {:error, :email_mismatch}
        true -> {:ok, user}
      end
    end)
    |> Ecto.Multi.run(:verify_still_valid, fn _repo, _ ->
      fresh =
        from(i in Invite,
          where: i.id == ^invite.id and is_nil(i.accepted_at) and i.expires_at > ^DateTime.utc_now()
        )
        |> Repo.one()

      if fresh, do: {:ok, fresh}, else: {:error, :expired}
    end)
    |> Ecto.Multi.update(:invite, fn %{verify_still_valid: fresh} -> Invite.accept_changeset(fresh) end)
    |> Ecto.Multi.insert(:membership, fn %{check_invite: user} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        organization_id: invite.organization_id,
        role: invite.role
      })
    end)
  end
```
- [ ] **Step 2:** Rewrite `accept_invite/2` to wrap it (preserve return shapes + the post-commit `set_2fa_deadline_if_needed`):
```elixir
  def accept_invite(%Invite{} = invite, %{id: _, email: _} = user) do
    invite
    |> invite_acceptance_multi(fn _ -> user end)
    |> Repo.transaction()
    |> case do
      {:ok, result} ->
        org = get_organization!(invite.organization_id)
        set_2fa_deadline_if_needed(result.membership, org)
        {:ok, result}

      {:error, :check_invite, reason, _} -> {:error, reason}
      {:error, :verify_still_valid, :expired, _} -> {:error, :expired}
      {:error, _op, changeset, _} -> {:error, changeset}
    end
  end
```
- [ ] **Step 3:** Add a join-request changeset helper for the atomic join path (used in Task 2):
```elixir
  @doc "Builds an unsaved JoinRequest changeset (for composing into a Multi)."
  def build_join_request(user_id, org_id) do
    JoinRequest.changeset(%JoinRequest{}, %{user_id: user_id, organization_id: org_id})
  end
```
(Confirm `JoinRequest` is aliased in `organizations.ex`; `create_join_request/2` stays as-is for the existing-user path.)
- [ ] **Step 4:** Run `mix test test/estimate/accounts_test.exs test/estimate_web/live/onboarding_test.exs` — accept_invite behavior + invite-mismatch/forced-email must still pass. Then full suite + `mix compile --warnings-as-errors --force`. Commit: `refactor: extract composable invite_acceptance_multi`.

---

### Task 2: Atomic register-and-join context functions + unit tests

**Files:** Modify `lib/estimate/accounts.ex`. Test: `test/estimate/accounts_test.exs` (add).

**Interfaces (produced):**
- `Accounts.register_user_and_accept_invite(user_attrs, %Invite{}) :: {:ok, %User{}} | {:error, :expired | :email_mismatch | Ecto.Changeset.t()}` — atomic: user rolled back if invite step fails.
- `Accounts.register_user_and_request_join(user_attrs, org_id) :: {:ok, %User{}} | {:error, Ecto.Changeset.t()}` — atomic.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:ecto-nested-associations`.
- [ ] **Step 1:** Add both (mirror `register_user_with_organization/2`'s shape; `Organizations` is already referenced by Accounts for `Organization`/`Membership`):
```elixir
  def register_user_and_accept_invite(user_attrs, %Estimate.Organizations.Invite{} = invite) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.registration_changeset(%User{}, user_attrs))
    |> Ecto.Multi.merge(fn %{user: user} ->
      Estimate.Organizations.invite_acceptance_multi(invite, fn _ -> user end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, membership: membership}} ->
        org = Estimate.Organizations.get_organization!(invite.organization_id)
        Estimate.Organizations.set_2fa_deadline_if_needed(membership, org)
        {:ok, user}

      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :check_invite, reason, _} -> {:error, reason}
      {:error, :verify_still_valid, :expired, _} -> {:error, :expired}
      {:error, _op, changeset, _} -> {:error, changeset}
    end
  end

  def register_user_and_request_join(user_attrs, org_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.registration_changeset(%User{}, user_attrs))
    |> Ecto.Multi.insert(:join_request, fn %{user: user} ->
      Estimate.Organizations.build_join_request(user.id, org_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :join_request, changeset, _} -> {:error, changeset}
    end
  end
```
- [ ] **Step 2:** Write context tests in `accounts_test.exs` (the core correctness pins — TDD: write, watch fail if you invert, then green):
```elixir
  describe "register_user_and_accept_invite/2 (atomic)" do
    setup do
      %{user: inviter, organization: org} = Estimate.AccountsFixtures.user_with_organization_fixture()
      invite = Estimate.AccountsFixtures.invite_fixture(org, inviter, %{email: "invitee@example.com", role: "member"})
      %{org: org, invite: invite}
    end

    test "valid invite: creates user + membership atomically", %{invite: invite} do
      attrs = %{email: "invitee@example.com", name: "Invitee", password: "a_valid_password!"}
      assert {:ok, user} = Accounts.register_user_and_accept_invite(attrs, invite)
      assert user.email == "invitee@example.com"
      assert Estimate.Organizations.get_user_membership(user.id, invite.organization_id)
    end

    test "email mismatch: no user persisted (rolled back)", %{invite: invite} do
      attrs = %{email: "someone-else@example.com", name: "X", password: "a_valid_password!"}
      assert {:error, :email_mismatch} = Accounts.register_user_and_accept_invite(attrs, invite)
      refute Accounts.get_user_by_email("someone-else@example.com")
    end

    test "invalid user attrs: nothing persisted", %{invite: invite} do
      assert {:error, %Ecto.Changeset{}} =
               Accounts.register_user_and_accept_invite(%{email: "bad", name: "", password: "x"}, invite)
      refute Accounts.get_user_by_email("bad")
    end
  end

  describe "register_user_and_request_join/2 (atomic)" do
    test "creates user + join request atomically" do
      %{organization: org} = Estimate.AccountsFixtures.user_with_organization_fixture()
      attrs = %{email: "joiner@example.com", name: "Joiner", password: "a_valid_password!"}
      assert {:ok, user} = Accounts.register_user_and_request_join(attrs, org.id)
      assert Enum.any?(Estimate.Organizations.list_pending_join_requests(org.id), &(&1.user_id == user.id))
    end

    test "invalid user attrs: nothing persisted" do
      %{organization: org} = Estimate.AccountsFixtures.user_with_organization_fixture()
      assert {:error, %Ecto.Changeset{}} =
               Accounts.register_user_and_request_join(%{email: "bad", name: "", password: "x"}, org.id)
      refute Accounts.get_user_by_email("bad")
    end
  end
```
(Verify `Estimate.AccountsFixtures.invite_fixture/3` exists — added in the auth-characterization work. Adjust `get_user_membership`/`list_pending_join_requests` names to the real `Organizations` API if they differ.)
- [ ] **Step 3:** `mix test test/estimate/accounts_test.exs` green; full suite; compile clean. Commit: `feat: atomic register_user_and_accept_invite / register_user_and_request_join`.

---

### Task 3: Wire the 3 LiveViews + flip/add characterization tests

**Files:** Modify `registration.ex`, `invite_live/accept.ex`, `join_request_live/new.ex`. Test: `test/estimate_web/live/onboarding_test.exs` (update + add).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1: registration.ex invite-code save** — replace the nested `register_user` → `get_valid_invite_by_code` → `accept_invite` logic (lines 118-147) with:
```elixir
  def handle_event("save", %{"user" => user_params, "invite_code" => code}, socket) do
    case Organizations.get_valid_invite_by_code(code) do
      nil ->
        {:noreply,
         socket
         |> assign(invite_code: code, invite_code_error: "Invalid or expired invite code")
         |> assign(check_errors: true)}

      invite ->
        case Accounts.register_user_and_accept_invite(user_params, invite) do
          {:ok, _user} ->
            {:noreply, assign(socket, trigger_submit: true)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(invite_code: code, invite_code_error: "Could not join organization")
             |> assign(check_errors: true)}
        end
    end
  end
```
(Look up the invite by code FIRST so a bogus code never inserts a user; on changeset error re-render the user form; note `trigger_submit` still drives the post-to-login auto-submit.)
- [ ] **Step 2: invite_live/accept.ex `register_and_accept`** — replace the `register_user` → `accept_invite` nesting with `Accounts.register_user_and_accept_invite(user_params, invite)` (preserve the `invite.email` forcing on `user_params` BEFORE the call, and the same success flash/redirect + error flash/redirect).
- [ ] **Step 3: join_request/new.ex `register_and_request_join`** — replace `register_user` → `create_join_request` nesting with `Accounts.register_user_and_request_join(user_params, org.id)` (same success/error flashes + redirect).
- [ ] **Step 4: Flip the characterization test** in `onboarding_test.exs` — the "registration invite-code path (non-atomic)" test currently asserts a bogus code STILL persists the user. Rewrite it to assert the FIXED behavior:
```elixir
  describe "registration invite-code path (atomic)" do
    test "bogus invite code persists NO user (rolled back / never inserted)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      lv |> element(~s(input[phx-click="toggle_invite_code"])) |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save"]),
          user: %{name: "Reg User", email: "reg-user@example.com", password: "a_valid_password!"},
          invite_code: "BOGUS-CODE"
        )
        |> render_submit()

      assert html =~ "Invalid or expired invite code"
      refute Estimate.Accounts.get_user_by_email("reg-user@example.com")
    end
  end
```
- [ ] **Step 5: Add a pin for the join-request path** (currently untested) in `onboarding_test.exs` — success path creates user + join request and redirects to log in:
```elixir
  describe "join-request registration" do
    test "register-and-request-join creates the user + a pending request", %{conn: conn} do
      %{organization: org} = Estimate.AccountsFixtures.user_with_organization_fixture()

      {:ok, lv, _html} = live(conn, ~p"/organizations/#{org.id}/join")

      {:error, {:redirect, %{to: to, flash: flash}}} =
        lv
        |> form(~s(form[phx-submit="register_and_request_join"]),
          user: %{name: "Joiner", email: "joiner@example.com", password: "a_valid_password!"}
        )
        |> render_submit()

      assert to == "/users/log_in"
      assert flash["info"] =~ "pending approval"
      assert Estimate.Accounts.get_user_by_email("joiner@example.com")
    end
  end
```
(Adjust the form selector / flash text to the real ones if they differ. The redirect flash is signed — if the match shape differs, use `follow_redirect`.)
- [ ] **Step 6:** `mix test test/estimate_web/live/onboarding_test.exs test/estimate/accounts_test.exs test/estimate_web/controllers/user_session_controller_test.exs` green; full suite; compile clean. Commit: `fix: make invite/join registration atomic across all 3 entry points`.

---

## Self-Review
**Coverage:** all 3 non-atomic call sites fixed via one shared multi; accept_invite/2 behavior preserved (pinned); characterization flipped to the correct behavior; join-request path gains its first test. **Deferred (Plan B):** `registration.ex`/`account_settings.ex` presentational decomposition (behavior-preserving) — separate PR.
**Placeholder scan:** none — Multi + context fns + tests are complete; the few "verify the real name" notes are concrete lookups with fallbacks.
**Type consistency:** `invite_acceptance_multi/2` steps (`:check_invite`/`:verify_still_valid`/`:invite`/`:membership`) referenced consistently in accept_invite/2 + register_user_and_accept_invite/2 error matches. Return shapes mirror `register_user_with_organization/2`.
