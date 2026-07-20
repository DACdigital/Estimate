defmodule EstimateWeb.MCP.SerializersWriteTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias EstimateWeb.MCP.{Serializers, Write}

  test "changeset_errors renders readable messages" do
    cs = Estimate.CRM.Customer.changeset(%Estimate.CRM.Customer{}, %{"name" => ""})
    msg = Serializers.changeset_errors(cs)
    assert msg =~ "key:"
    assert msg =~ "name:"
  end

  test "url helpers embed org + ids" do
    assert Serializers.customer_url("O", "C") =~ "/org/O/customers/C"
    assert Serializers.project_url("O", "P") =~ "/org/O/projects/P"

    assert Serializers.estimation_url("O", "P", "E") =~
             "/org/O/projects/P/estimations/E/estimator"
  end

  test "resolve_currency: nil passes through, unknown errors, known resolves" do
    %{organization: org} = user_with_organization_fixture()
    assert Write.resolve_currency(nil, org.id) == {:ok, nil}
    assert Write.resolve_currency("", org.id) == {:ok, nil}
    assert {:error, msg} = Write.resolve_currency("ZZZ", org.id)
    assert msg =~ "ZZZ"
    assert {:ok, id} = Write.resolve_currency("EUR", org.id)
    assert is_binary(id)
  end
end
