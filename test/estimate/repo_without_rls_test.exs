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
  end
end
