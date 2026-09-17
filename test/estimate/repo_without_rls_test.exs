defmodule Estimate.RepoWithoutRLSTest do
  use Estimate.DataCase, async: false

  defp current_user_role do
    %{rows: [[role]]} = Repo.query!("SELECT current_user", [])
    role
  end

  defp current_org_setting do
    %{rows: [[org]]} = Repo.query!("SELECT current_setting('app.current_org_id', true)", [])
    org
  end

  defp current_user_setting do
    %{rows: [[user]]} = Repo.query!("SELECT current_setting('app.current_user_id', true)", [])
    user
  end

  describe "without_rls/1" do
    test "resets role for fun, then restores role and RLS context on return" do
      org_id = Ecto.UUID.generate()

      Repo.assume_app_role()
      Repo.set_org_context(org_id)
      assert current_user_role() == "estimate_app"

      result =
        Repo.without_rls(fn ->
          refute current_user_role() == "estimate_app"
          :fun_return_value
        end)

      assert result == :fun_return_value
      assert current_user_role() == "estimate_app"
      assert current_org_setting() == org_id
    end

    test "restores role and RLS context even when fun raises" do
      org_id = Ecto.UUID.generate()

      Repo.assume_app_role()
      Repo.set_org_context(org_id)
      assert current_user_role() == "estimate_app"

      assert_raise RuntimeError, "boom", fn ->
        Repo.without_rls(fn -> raise "boom" end)
      end

      assert current_user_role() == "estimate_app"
      assert current_org_setting() == org_id
    end

    test "runs fun as the table-owning login role, which bypasses RLS" do
      login_role = current_user_role()
      refute login_role == "estimate_app"

      Repo.assume_app_role()

      assert Repo.without_rls(fn -> current_user_role() end) == login_role

      %{rows: [[owns_all]]} =
        Repo.query!(
          """
          SELECT bool_and(pg_has_role($1, c.relowner, 'USAGE'))
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity
          """,
          [login_role]
        )

      assert owns_all
      assert current_user_role() == "estimate_app"
    end

    # FORCE ROW LEVEL SECURITY is transactional DDL, so the sandbox rolls it
    # back; this exercises the assertion's raise path and proves the after
    # clause still restores role + context when the assertion (not fun) fails.
    test "raises and restores state when the login role would not bypass RLS" do
      org_id = Ecto.UUID.generate()
      Repo.query!("ALTER TABLE projects FORCE ROW LEVEL SECURITY", [])

      Repo.assume_app_role()
      Repo.set_org_context(org_id)

      assert_raise RuntimeError, ~r/without_rls: role .* does not bypass RLS/, fn ->
        Repo.without_rls(fn -> flunk("fun must not run when the bypass assertion fails") end)
      end

      assert current_user_role() == "estimate_app"
      assert current_org_setting() == org_id
    end
  end

  describe "with_org_context/2 state restoration" do
    test "sets role+org(+user) for fun, then restores prior connection state on return" do
      org_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      login_role = current_user_role()
      login_org = current_org_setting()
      login_user = current_user_setting()
      refute login_role == "estimate_app"
      assert login_org in [nil, ""]
      assert login_user in [nil, ""]

      Repo.put_user_id(user_id)

      result =
        Repo.with_org_context(org_id, fn ->
          {current_user_role(), current_org_setting(), current_user_setting()}
        end)

      assert result == {"estimate_app", org_id, user_id}
      assert current_user_role() == login_role
      # nil (never-set) is normalized to "" on restore — current_setting can't
      # tell "never set" from "explicitly cleared"; same as without_rls's `prev_org || ""`.
      assert current_org_setting() == (login_org || "")
      assert current_user_setting() == (login_user || "")
    end

    test "restores role and RLS context even when fun raises" do
      org_id = Ecto.UUID.generate()

      login_role = current_user_role()
      login_org = current_org_setting()

      assert_raise RuntimeError, "boom", fn ->
        Repo.with_org_context(org_id, fn -> raise "boom" end)
      end

      assert current_user_role() == login_role
      assert current_org_setting() == (login_org || "")
    end

    test "without_rls nested inside with_org_context keeps the outer org context after the inner call returns" do
      org_id = Ecto.UUID.generate()

      login_role = current_user_role()
      login_org = current_org_setting()

      result =
        Repo.with_org_context(org_id, fn ->
          inner_role = Repo.without_rls(fn -> current_user_role() end)
          {inner_role, current_user_role(), current_org_setting()}
        end)

      assert {inner_role, resumed_role, resumed_org} = result
      refute inner_role == "estimate_app"
      assert resumed_role == "estimate_app"
      assert resumed_org == org_id

      assert current_user_role() == login_role
      assert current_org_setting() == (login_org || "")
    end

    test "with_org_context nested inside without_rls keeps the reset role after the inner call returns" do
      org_id = Ecto.UUID.generate()

      login_role = current_user_role()
      login_org = current_org_setting()

      result =
        Repo.without_rls(fn ->
          reset_role = current_user_role()

          inner_result =
            Repo.with_org_context(org_id, fn ->
              {current_user_role(), current_org_setting()}
            end)

          {reset_role, inner_result, current_user_role(), current_org_setting()}
        end)

      assert {reset_role, inner_result, resumed_role, resumed_org} = result
      assert inner_result == {"estimate_app", org_id}
      assert resumed_role == reset_role
      assert resumed_org in [nil, ""]

      assert current_user_role() == login_role
      assert current_org_setting() == (login_org || "")
    end
  end

  describe "with_org_context/2 statement count" do
    setup do
      test_pid = self()
      handler = "ctx-count-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:estimate, :repo, :query],
        fn _e, _m, meta, _ -> send(test_pid, {:query, meta.query}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    defp queries(acc \\ []) do
      receive do
        {:query, q} -> queries([q | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    test "a flat call issues exactly 3 statements: capture, set, restore" do
      org_id = Ecto.UUID.generate()
      Repo.put_user_id(Ecto.UUID.generate())
      queries()

      Repo.with_org_context(org_id, fn -> :ok end)

      [capture, set, restore] = queries()
      assert capture =~ "current_setting('app.current_org_id'"
      assert set =~ "set_config('role'"
      assert set =~ "set_config('app.current_org_id'"
      assert set =~ "set_config('app.current_user_id'"
      assert restore =~ "set_config('role'"
    end

    test "a nested call with the same org and user issues no statements" do
      org_id = Ecto.UUID.generate()
      Repo.put_user_id(Ecto.UUID.generate())
      queries()

      Repo.with_org_context(org_id, fn ->
        queries()
        inner = Repo.with_org_context(org_id, fn -> current_user_role() end)
        assert inner == "estimate_app"
        # Only the fun's own "SELECT current_user" appears — the no-op nested
        # call adds zero wrapper (capture/set/restore) statements of its own.
        assert queries() == ["SELECT current_user"]
      end)

      assert Process.get(:rls_ctx) == nil
    end

    test "a nested call with a different org runs the full path and restores the outer context" do
      org_a = Ecto.UUID.generate()
      org_b = Ecto.UUID.generate()
      Repo.put_user_id(Ecto.UUID.generate())

      Repo.with_org_context(org_a, fn ->
        queries()
        Repo.with_org_context(org_b, fn -> assert current_org_setting() == org_b end)
        # 3 wrapper statements (capture, set, restore) plus the fun's own
        # "SELECT current_setting(...)" from current_org_setting/0.
        assert length(queries()) == 4
        assert current_org_setting() == org_a
        assert current_user_role() == "estimate_app"
      end)
    end

    test "the marker is cleared even when fun raises" do
      org_id = Ecto.UUID.generate()

      assert_raise RuntimeError, "boom", fn ->
        Repo.with_org_context(org_id, fn -> raise "boom" end)
      end

      assert Process.get(:rls_ctx) == nil
    end
  end
end
