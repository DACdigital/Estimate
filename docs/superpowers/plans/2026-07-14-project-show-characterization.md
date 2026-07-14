# ProjectLive.Show Characterization Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Before writing tests invoke `elixir-phoenix-guide:testing-essentials`. Steps use checkbox (`- [ ]`).

**Goal:** Pin the *current* behavior of `EstimateWeb.ProjectLive.Show` (`lib/estimate_web/live/project_live/show.ex`, 1568 lines, 38 events, 7 clusters, ~zero LiveView coverage) with a comprehensive characterization suite, so the upcoming decomposition (thin router + per-feature `:live_handlers` modules, reusing the members template) has a safety net. This is the 3rd god-LiveView; same recipe that just shipped for members.

**Architecture:** Connected LiveView tests via `Phoenix.LiveViewTest`. One file `test/estimate_web/live/project_live/show_test.exs` with describe blocks per cluster (split later only if it grows unwieldy). Tests document CURRENT behavior — **GREEN on first run**. A red characterization test means the plan's expected value is wrong OR a latent bug was found: STOP and report, never edit `lib/` in this increment.

**Tech Stack:** Elixir ~> 1.15, Phoenix.LiveView 1.1, ExUnit (`async: true`), Ecto sandbox.

## Global Constraints
- **Characterization, not TDD.** Tests pin existing behavior → they pass immediately. Do NOT modify any file under `lib/`. If a test can't pass without a `lib/` change, the behavior differs from this plan — report it (`DONE_WITH_CONCERNS`), don't touch `lib/`.
- **No DB/schema changes.** Test-only work.
- All tests: `use EstimateWeb.ConnCase, async: true`; `import Phoenix.LiveViewTest`; `import Estimate.AccountsFixtures`, `Estimate.PortfolioFixtures`, `Estimate.CRMFixtures`, `Estimate.EstimationEngineFixtures` (add per task as needed).
- Route is **path-derived** (no session org/project): `~p"/org/#{org.id}/projects/#{project.id}"` (+ `/collaborators`, `/estimations`, `/estimations/new`). A viewer needs `log_in_user(conn, user)` + a `Membership` in the org, and to reach the project must be an **org-admin OR a project collaborator** (any role).
- `mix compile --warnings-as-errors --force` clean; full `mix test` green (`mix precommit` gate).
- Branch `refactor/project-show-characterize` off `master` (currently `d0fa875`).

## House idioms (verified against members_test.exs + the existing suite)
- Mount: `{:ok, lv, html} = live(conn, path)`; non-authorized mount returns `{:error, {:redirect, %{to: ...}}}`.
- Read assigns: `defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns`.
- Push event by name (for authz gating — a viewer's DOM omits the gated controls): `render_click(lv, "save", %{"project" => %{...}})`. `handle_event/3` matches on the event NAME regardless of the original binding.
- **Between gated pushes on the same `lv`, clear the error flash** so a prior "Not authorized" can't bleed into the next assertion: `render_click(lv, "lv:clear-flash", %{"key" => "error"})` (a real built-in LiveView event).
- In-place flash (no redirect): `assert html =~ "..."` on the `render_click`/`render_submit` return.
- Redirect assertions: `assert {:error, {:redirect, %{to: path}}} = live(...)`; for `push_navigate` in a handler: `assert_redirect(lv, path)` or assert the returned `{:error, {:live_redirect, ...}}` from `render_click`.
- Clipboard/download: `assert_push_event(lv, "copy_to_clipboard", %{text: _})` / `assert_push_event(lv, "download_file", %{filename: "estimation-schema.json"})`.
- Forms: `lv |> form(~s(form[phx-submit="save"]), %{"project" => %{...}}) |> render_submit()`.

## Role-matrix setup cheatsheet (exact fixtures, from the survey)
```elixir
# org + owner-of-org
%{user: owner, organization: org} = user_with_organization_fixture()

# a project whose creator is its "owner" collaborator:
project = project_fixture(nil, owner)                 # owner is org-owner AND project-owner
# (project_fixture(customer, user) derives org from user's membership, makes user the owner collaborator)

# org admin (NOT a project collaborator) — can still view + full perms via admin?:
admin = user_fixture(); membership_fixture(admin, org, "admin")

# editor / viewer collaborators (must be org members first):
editor = user_fixture(); membership_fixture(editor, org, "member")
{:ok, _} = Estimate.Portfolio.add_collaborator(project.id, editor.id, "editor")
viewer = user_fixture(); membership_fixture(viewer, org, "member")
{:ok, _} = Estimate.Portfolio.add_collaborator(project.id, viewer.id, "viewer")

# org member, NOT a collaborator → redirected at show mount to /projects
outsider_member = user_fixture(); membership_fixture(outsider_member, org, "member")

# non-member → halted by OrgAuth to /organizations ; anonymous → /users/log_in
```
Permission truth (computed at mount): `can_edit_project` = org-admin OR collab ∈ {owner,editor}; `can_delete_project` = org-admin OR collab==owner; `can_manage_collaborators` = org-admin OR collab==owner. Gated events flash exactly **"Not authorized"** for the unauthorized.

---

### Task 1: Scaffolding + mount / access-gate / permissions / tabs + authz gating

**Files:** Create `test/estimate_web/live/project_live/show_test.exs`.

**Interfaces (produced, reused by Tasks 2–6):** `assigns/1`; `setup_project/1` (setup yielding `%{org:, owner:, project:}`); `add_collab/3` (`(project, org, role) -> %{user:, collaborator:}`); `path/1` (`project -> ~p"/org/#{org_id}/projects/#{id}"` — needs org_id; make it `path/2` or bake org into the struct read).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:testing-essentials`.
- [ ] **Step 1: module skeleton + helpers + mount/perimeter/tabs tests.**
```elixir
defmodule EstimateWeb.ProjectLive.ShowTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.PortfolioFixtures

  alias Estimate.Portfolio

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns
  defp path(org, project), do: ~p"/org/#{org.id}/projects/#{project.id}"

  defp setup_project(_) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    %{org: org, owner: owner, project: project}
  end

  # add an org-member + project collaborator of the given role
  defp add_collab(project, org, role) do
    user = user_fixture()
    _ = membership_fixture(user, org, "member")
    {:ok, collab} = Portfolio.add_collaborator(project.id, user.id, role)
    %{user: user, collaborator: collab}
  end

  describe "mount perimeter" do
    setup :setup_project

    test "project owner mounts overview", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, html} = live(log_in_user(conn, owner), path(org, project))
      assert assigns(lv).tab == :overview
      assert assigns(lv).project.id == project.id
      assert assigns(lv).can_edit_project and assigns(lv).can_delete_project and assigns(lv).can_manage_collaborators
      assert html =~ project.name
    end

    test "org admin (non-collaborator) mounts with full perms", %{conn: conn, org: org, project: project} do
      admin = user_fixture(); _ = membership_fixture(admin, org, "admin")
      {:ok, lv, _} = live(log_in_user(conn, admin), path(org, project))
      assert assigns(lv).can_edit_project and assigns(lv).can_delete_project and assigns(lv).can_manage_collaborators
    end

    test "editor collaborator: can edit, cannot delete/manage", %{conn: conn, org: org, project: project} do
      %{user: editor} = add_collab(project, org, "editor")
      {:ok, lv, _} = live(log_in_user(conn, editor), path(org, project))
      assert assigns(lv).can_edit_project
      refute assigns(lv).can_delete_project
      refute assigns(lv).can_manage_collaborators
    end

    test "viewer collaborator: no edit/delete/manage", %{conn: conn, org: org, project: project} do
      %{user: viewer} = add_collab(project, org, "viewer")
      {:ok, lv, _} = live(log_in_user(conn, viewer), path(org, project))
      refute assigns(lv).can_edit_project
      refute assigns(lv).can_delete_project
      refute assigns(lv).can_manage_collaborators
    end

    test "org member who is not a collaborator is redirected to projects", %{conn: conn, org: org, project: project} do
      m = user_fixture(); _ = membership_fixture(m, org, "member")
      assert {:error, {:redirect, %{to: to}}} = live(log_in_user(conn, m), path(org, project))
      assert to =~ "/org/#{org.id}/projects"
    end

    test "non-member is redirected to /organizations", %{conn: conn, org: org, project: project} do
      stranger = user_fixture()
      assert {:error, {:redirect, %{to: "/organizations"}}} = live(log_in_user(conn, stranger), path(org, project))
    end

    test "anonymous is redirected to log in", %{conn: conn, org: org, project: project} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, path(org, project))
      assert to =~ "/users/log_in"
    end
  end

  describe "tabs (handle_params)" do
    setup :setup_project

    test "collaborators/estimations tabs load their data", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), path(org, project))
      assert assigns(lv).tab == :overview

      {:ok, lv2, _} = live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")
      assert assigns(lv2).tab == :collaborators
      assert is_list(assigns(lv2).collaborators) and assigns(lv2).collaborators != []  # owner is a collaborator

      {:ok, lv3, _} = live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/estimations")
      assert assigns(lv3).tab == :estimations
      assert is_list(assigns(lv3).deleted_estimations)

      {:ok, lv4, _} = live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/estimations/new")
      assert assigns(lv4).show_new_estimation_modal == true
    end
  end

  describe "authorization gating (viewer pushing gated events)" do
    setup :setup_project

    setup %{conn: conn, org: org, project: project} do
      %{user: viewer} = add_collab(project, org, "viewer")
      {:ok, lv, _} = live(log_in_user(conn, viewer), path(org, project))
      %{lv: lv, project: project, org: org}
    end

    test "gated events flash Not authorized for a viewer and mutate nothing", %{lv: lv} do
      pushes = [
        {"save", %{"project" => %{"name" => "X"}}},
        {"delete_project", %{}},
        {"create_estimation", %{"estimation" => %{"name" => "E"}}},
        {"set_current_estimation", %{"id" => Ecto.UUID.generate()}},
        {"delete_estimation", %{"id" => Ecto.UUID.generate()}},
        {"restore_estimation", %{"id" => Ecto.UUID.generate()}},
        {"permanent_delete_estimation", %{"id" => Ecto.UUID.generate()}},
        {"add_collaborator", %{}},
        {"change_collaborator_role", %{"id" => Ecto.UUID.generate(), "role" => "editor"}},
        {"remove_collaborator", %{}}
      ]

      for {event, payload} <- pushes do
        render_click(lv, "lv:clear-flash", %{"key" => "error"})
        assert render_click(lv, event, payload) =~ "Not authorized",
               "expected #{event} to be authorization-gated for a viewer"
      end
    end
  end
end
```
NOTE: verify each gated event's ungated path would diverge from "Not authorized" for a viewer (the survey confirms all 10 return the "Not authorized" flash on the unauthorized branch). `delete_project`/`remove_collaborator`/`add_collaborator` take `_`/empty params on the gate path. If any event's unauthorized branch has a *different* string, pin the real one and note it.
- [ ] **Step 2:** `mix test test/estimate_web/live/project_live/show_test.exs` — GREEN. If a redirect target or perms value differs, pin the real one + report.
- [ ] **Step 3:** `mix compile --warnings-as-errors --force` clean.
- [ ] **Step 4: Commit** `test: characterize project show mount/perimeter/tabs/authz-gating`.

---

### Task 2: Cluster A (details) + B (danger-zone delete) + C (dashboard tab)

**Files:** Modify `show_test.exs` (append; reuse helpers).

Behaviors to pin (exact strings from the survey):
- **A `validate`** → sets `form` with `action: :validate`, no flash. **`save`** (owner/editor/admin): valid → flash **"Project updated"**, `project` reloaded, `form` reset; invalid changeset (e.g. bad `repository_url` not `^https?://`, or blank required `name`) → `form` shows errors, project unchanged; unauthorized (viewer via direct push) → **"Not authorized"**.
- **B danger-zone state machine:** `confirm_delete_project` → `deleting_project: true`, `delete_impact` set (map with estimation_count/task_count/collaborator_count), `delete_confirmation_input: ""`. `validate_delete_confirmation %{"value"=>v}` → `delete_confirmation_input: v`. `cancel_delete_project` → `deleting_project: false`. `delete_project`: (a) unauthorized → "Not authorized"; (b) authorized but `delete_confirmation_input != project.name` → also "Not authorized" (the gate is `can_delete AND name-match`); (c) authorized + exact name → **"Project deleted"** + redirect to `.../projects` (assert via `assert_redirect`), project soft/hard-deleted per `Portfolio.delete_project/1`.
- **C `set_dashboard_tab`:** valid tab in `~w(by_role by_epic by_priority)` → `dashboard_tab` atom; invalid value → no-op (fallback clause).

- [ ] **Step 1: append describe blocks.** Full example for the delete state machine (the trickiest):
```elixir
  describe "project details" do
    setup :setup_project

    test "save updates the project (owner)", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), path(org, project))
      html =
        lv
        |> form(~s(form[phx-submit="save"]), %{"project" => %{"name" => "Renamed Project"}})
        |> render_submit()
      assert html =~ "Project updated"
      assert Portfolio.get_project_with_roles!(project.id, org.id).name == "Renamed Project"
    end

    test "save with invalid repository_url shows a changeset error, no update", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), path(org, project))
      html = render_click(lv, "save", %{"project" => %{"repository_url" => "ftp://nope"}})
      refute html =~ "Project updated"
      assert Portfolio.get_project_with_roles!(project.id, org.id).name == project.name
    end
  end

  describe "danger zone / delete project" do
    setup :setup_project

    test "confirm → type name → delete redirects", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), path(org, project))
      render_click(lv, "confirm_delete_project", %{})
      assert assigns(lv).deleting_project == true
      assert is_map(assigns(lv).delete_impact)

      render_click(lv, "validate_delete_confirmation", %{"value" => project.name})
      assert assigns(lv).delete_confirmation_input == project.name

      render_click(lv, "delete_project", %{})
      assert_redirect(lv, ~p"/org/#{org.id}/projects")
    end

    test "delete refused when typed name doesn't match", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), path(org, project))
      render_click(lv, "confirm_delete_project", %{})
      render_click(lv, "validate_delete_confirmation", %{"value" => "wrong"})
      html = render_click(lv, "delete_project", %{})
      assert html =~ "Not authorized"
      assert assigns(lv).deleting_project == false
      assert Portfolio.get_project_with_roles!(project.id, org.id)  # still exists
    end

    test "cancel resets delete state", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), path(org, project))
      render_click(lv, "confirm_delete_project", %{})
      render_click(lv, "cancel_delete_project", %{})
      assert assigns(lv).deleting_project == false
    end
  end

  describe "dashboard tab" do
    setup :setup_project

    test "set_dashboard_tab accepts valid, ignores invalid", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), path(org, project))
      for t <- ~w(by_role by_epic by_priority) do
        render_click(lv, "set_dashboard_tab", %{"tab" => t})
        assert assigns(lv).dashboard_tab == String.to_existing_atom(t)
      end
      render_click(lv, "set_dashboard_tab", %{"tab" => "bogus"})
      assert assigns(lv).dashboard_tab == :by_priority  # unchanged
    end
  end
```
- [ ] **Step 2:** run the file — GREEN. (If `delete_project` on the name-mismatch path returns a different flash than "Not authorized", pin the real one — the survey says the gate is `can_delete AND name-match` → "Not authorized".)
- [ ] **Step 3: Commit** `test: characterize project show details + danger-zone + dashboard tab`.

---

### Task 3: Cluster D part 1 — new-estimation modal state machine

**Files:** Modify `show_test.exs` (append). Needs `Estimate.EstimationEngineFixtures` (estimation_fixture) for copy-source prefill.

Behaviors to pin (survey §2 cluster D, §8 state machine 1):
- `open_estimation_modal` → `show_new_estimation_modal: true`, `estimation_source: "fresh"`, `modal_roles` built from templates, `modal_currency_id == project.currency_id`.
- `close_estimation_modal` → `show_new_estimation_modal: false`.
- `set_estimation_source %{"source"=>s}` for `"fresh"|"copy"|"template"|"json"` → `estimation_source: s`; for `"copy"` WITH ≥1 estimation → `estimation_form` name prefilled "Copy of <name>", `source_estimation_id` set, `modal_currency_id/currency` locked to source; JSON/others reset appropriately (`clear_json`).
- `add_modal_role` → `modal_roles` grows by 1 blank; `remove_modal_role %{"temp-id"=>id}` → drops that role; `reset_modal_roles` → rebuilt from templates; `reorder_modal_roles %{"ids"=>ids}` → reordered to match `ids`.
- `validate_estimation` general params → updates `modal_roles` from `roles[...]`, maybe currency; JSON branch (`%{"json_input"=>s}` with s≠"") → sets `json_parsed`/`json_error`, prefills form.

Give full code for open/close/set_source (incl. copy prefill) and the modal-role add/remove/reorder/reset; enumerate the rest with exact expected assigns.
- [ ] **Step 1:** append the modal-state describe block (full code for the state transitions; assert on `assigns(lv).estimation_source`, `.modal_roles` length/order, `.source_estimation_id`, `.modal_currency_id`, `.estimation_form.params["name"]`). Use `open_estimation_modal` to open, then drive.
- [ ] **Step 2:** run — GREEN. The modal-role temp-ids are generated; capture them from `assigns(lv).modal_roles` (each has a `temp_id`) rather than hardcoding. For `reorder`, pass the current ids reversed and assert the order flipped.
- [ ] **Step 3: Commit** `test: characterize project show new-estimation modal state`.

---

### Task 4: Cluster D part 2 — estimation creation (4 sources) + JSON events

**Files:** Modify `show_test.exs` (append).

Behaviors to pin:
- `create_estimation` (owner/editor/admin) success paths → flash **"Estimation created"** (fresh/template/json) or **"Estimation copied"** (copy); `show_new_estimation_modal: false`; `estimations` refreshed; `push_navigate` to the estimator (`assert_redirect`/`assert_patch` to `~p"/org/#{org.id}/projects/#{project.id}/estimations/#{new_id}/edit"` — confirm the exact target in `show.ex`).
  - **fresh** (`estimation_source:"fresh"`): a valid `estimation[name]` + valid `modal_roles` → created.
  - **copy** (`"copy"` + valid `source_estimation_id`): copies; cross-project source → **"Not authorized"** (guard `source_estimation.project_id == project.id`).
  - **template**: with a `selected_estimation_template_id`.
  - **json**: with `json_parsed` present; missing → the `:no_json` branch.
  - roles invalid (blank name/abbrev, non-copy) → **"All roles must have a name and abbreviation"**; generic error → **"Could not create estimation"**; unauthorized → **"Not authorized"**.
- `json_file_uploaded %{"content"=>c}` → validates JSON, sets json assigns. `download_json_schema` → `assert_push_event(lv, "download_file", %{filename: "estimation-schema.json"})`. `copy_agent_prompt` → `assert_push_event(lv, "copy_to_clipboard", _)` + flash **"Agent prompt copied"**.

Pin at minimum: the **fresh** happy path (created + redirect + "Estimation created"), the **copy** happy path + the **cross-project copy guard** ("Not authorized"), the **roles-invalid** message, and the 3 JSON/prompt push events. Template/json full-creation may be lighter (assert the flash + estimations growth) since the deep engine logic is covered elsewhere — focus on the LiveView wiring + guards.
- [ ] **Step 1:** append; build a second project in another org to exercise the cross-project copy guard (`estimation_fixture` on a foreign project, pass its id as `source_estimation_id`).
- [ ] **Step 2:** run — GREEN. Confirm the post-create redirect target string against `show.ex` (`push_navigate`), and the exact "created"/"copied" strings.
- [ ] **Step 3: Commit** `test: characterize project show estimation creation + json events`.

---

### Task 5: Cluster E (estimation list) + F (trash)

**Files:** Modify `show_test.exs` (append). Uses `estimation_fixture(project)`.

Behaviors to pin:
- **E:** `set_current_estimation %{"id"=>id}` (owner) → **"Estimation…current"** wait: survey says success sets `current_estimation`/`estimations`, no explicit success flash listed — pin the ACTUAL (assert `assigns(lv).current_estimation.id == id`; assert flash only if one is emitted); cross-project id → **"Not authorized"**; error → **"Could not set current estimation"**. `confirm_delete_estimation %{"id"=>id}` → `deleting_estimation: id`; `cancel_delete_estimation` → `nil`; `delete_estimation %{"id"=>id}`: `is_current` → **"Cannot delete current estimation"**; cross-project → **"Not authorized"**; ok → **"Estimation moved to trash"** + moves to `deleted_estimations`; unauthorized (viewer) → "Not authorized".
- **F:** `toggle_trash` → `show_trash` flips; `restore_estimation %{"id"=>id}` (needs the id in `deleted_estimations`) → **"Estimation restored"** + back in `estimations`; not in list → **"Estimation not found"**; unauthorized → "Not authorized". `confirm_permanent_delete`/`cancel_permanent_delete` → set/clear `permanently_deleting`. `permanent_delete_estimation %{"id"=>id}` → **"Estimation permanently deleted"** (removed from `deleted_estimations`); not found → **"Estimation not found"**; unauthorized → "Not authorized".

Setup note: `project_fixture` + `estimation_fixture(project)` — the FIRST estimation auto-becomes `is_current` (survey §5). Create TWO estimations so you have a non-current one to delete (deleting the current is blocked). To populate `deleted_estimations`, delete one first (via the event or `EstimationEngine.soft_delete_estimation/1` in setup) then visit the estimations tab / read the assign.
- [ ] **Step 1:** append E + F describe blocks. For the "delete current is blocked" test, target the `is_current` estimation and assert "Cannot delete current estimation". For trash, soft-delete a non-current estimation in setup, mount the estimations tab, then exercise restore/permanent-delete.
- [ ] **Step 2:** run — GREEN. Pin the ACTUAL success flash of `set_current_estimation` (assert the assign transition regardless; add the flash assertion only if one exists — check `show.ex:998-1024`).
- [ ] **Step 3: Commit** `test: characterize project show estimation list + trash`.

---

### Task 6: Cluster G — collaborators (dropdown + add/change/remove + last-owner)

**Files:** Modify `show_test.exs` (append). Mount the **collaborators** tab path so `collaborators`/`available_members` are populated.

Behaviors to pin (survey §2 G, §3 predicates, §8 state machine 4):
- Member-picker: `open_member_dropdown`/`close_member_dropdown` → `show_member_dropdown` true/false; `collaborator_form_change %{"member_search"=>s,"collaborator_role"=>r}` → `member_search`/`selected_role`/`show_member_dropdown`; `select_member %{"user-id"=>id}` → `selected_member` set (no-op for unknown id); `clear_selected_member` → nil + `member_search: ""`.
- `add_collaborator` (owner/admin) with a `selected_member` → **"Collaborator added"** + `collaborators` grows + form reset (`selected_member: nil`, `selected_role: "viewer"`); no member selected → silent no-op; unauthorized (viewer/editor) → **"Not authorized"**.
- `change_collaborator_role %{"id"=>id,"role"=>r}` (owner/admin) → **"Role updated"**; changing YOUR OWN role → **"Not authorized"** (`can_change_role?` = can_manage AND collab.user_id != current_user.id); unauthorized → "Not authorized".
- `confirm_remove_collaborator %{"id"=>id}` → `removing_collaborator` set; `cancel_remove_collaborator` → nil; `remove_collaborator`: removing YOURSELF → "Not authorized" (`can_remove_collaborator?` false for self); removing the **last owner** → **"Cannot remove the last project owner"**; ok → **"Collaborator removed"** + `collaborators` shrinks; unauthorized → "Not authorized".

Setup: owner (project owner) + add an editor + a second owner (`add_collaborator(project.id, u.id, "owner")`) so you can (a) remove a non-last owner and (b) test last-owner protection by trying to remove down to the final owner. For "change own role"/"remove self" use the acting user's own collaborator id.
- [ ] **Step 1:** append the collaborators describe block (full code for the dropdown state machine + the last-owner and self-guard cases — these are the highest-value pins).
- [ ] **Step 2:** run — GREEN. `list_available_members` only excludes existing collaborators; ensure the member you `select_member` is in `available_members` (an org member not yet a collaborator).
- [ ] **Step 3:** `mix compile --warnings-as-errors --force`; full `mix test` — entire suite green.
- [ ] **Step 4: Commit** `test: characterize project show collaborators (dropdown/add/change/remove/last-owner)`.

---

## Self-Review
**Coverage vs the 38 events:** Task 1 → mount/perimeter/tabs + gating for the 10 gated events. Task 2 → validate,save,confirm_delete_project,validate_delete_confirmation,cancel_delete_project,delete_project,set_dashboard_tab (7). Task 3 → open/close_estimation_modal,set_estimation_source,validate_estimation,add/remove/reorder/reset_modal_role (8). Task 4 → create_estimation,json_file_uploaded,download_json_schema,copy_agent_prompt (4). Task 5 → set_current_estimation,confirm/cancel/delete_estimation,toggle_trash,restore_estimation,confirm/cancel_permanent_delete,permanent_delete_estimation (9). Task 6 → collaborator_form_change,open/close_member_dropdown,select_member,clear_selected_member,add_collaborator,change_collaborator_role,confirm/cancel_remove_collaborator,remove_collaborator (10). Total covers all 38 + the 3 push events + every authz path + the redirect perimeter.
**Placeholder scan:** state-machine tests are full code; mechanical cases are enumerated with exact flash strings from the survey. The two "pin the actual flash" notes (set_current_estimation success; any divergent unauthorized string) are explicit observe-and-pin steps, not vague TODOs.
**Type consistency:** `assigns/1`, `setup_project/1`, `add_collab/3`, `path/2` defined in Task 1, reused throughout. Fixtures match the survey: `user_with_organization_fixture/0-2`, `project_fixture/2-3`, `membership_fixture/3`, `Portfolio.add_collaborator/3`, `estimation_fixture/1-2`, `EstimationEngine.soft_delete_estimation/1`.

## Unresolved questions
- Split into multiple test files? Plan uses one `show_test.exs` with per-cluster describes (~6 tasks append to it). If it grows unwieldy (>~800 lines) the implementer may split Cluster D/G into `show_estimations_test.exs`/`show_collaborators_test.exs` — flag if so.
- The `set_current_estimation` success flash + the exact post-create redirect target are "confirm against source" items (Tasks 4/5) — not blockers.
