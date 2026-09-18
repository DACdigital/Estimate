defmodule Estimate.Portfolio.CreateProjectRolesTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, CRMFixtures}
  alias Estimate.{Accounts, Portfolio}
  alias Estimate.Accounts.RoleTemplate

  test "a role template that cannot be copied surfaces as {:error, changeset} instead of raising" do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)

    # Diverge: make one seeded template invalid for ProjectRole (abbreviation "" fails
    # ProjectRole validate_required after cast empties it; role_templates has no CHECK on it).
    [tpl | _] = Accounts.list_role_templates(org.id)
    Repo.update_all(from(rt in RoleTemplate, where: rt.id == ^tpl.id), set: [abbreviation: ""])

    result = Portfolio.create_project(%{"name" => "P"}, customer.id, owner.id, org.id)

    assert {:error, %Ecto.Changeset{}} = result
    assert Repo.aggregate(Estimate.Portfolio.Project, :count) == 0
  end
end
