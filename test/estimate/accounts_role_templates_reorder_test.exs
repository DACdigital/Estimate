defmodule Estimate.AccountsRoleTemplatesReorderTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures
  alias Estimate.Accounts

  setup do
    %{organization: org} = user_with_organization_fixture()
    # orgs are seeded with default role templates
    ids = Accounts.list_role_templates(org.id) |> Enum.map(& &1.id)
    assert length(ids) >= 2
    %{org: org, ids: ids}
  end

  test "reorder_role_templates/2 applies the order", %{org: org, ids: [a, b | rest]} do
    new_order = [b, a | rest]
    assert :ok = Accounts.reorder_role_templates(org.id, new_order)
    assert Accounts.list_role_templates(org.id) |> Enum.map(& &1.id) == new_order
  end

  test "reorder_role_templates/2 rejects a stale (partial) id list untouched", %{
    org: org,
    ids: [a, b | _] = ids
  } do
    assert {:error, :stale_reorder} = Accounts.reorder_role_templates(org.id, [b, a])
    assert Accounts.list_role_templates(org.id) |> Enum.map(& &1.id) == ids
  end
end
