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
    # user_with_organization_fixture/0 auto-seeds 8 default role templates
    # (abbreviations BA/UX/MO/BE/FE/DO/AI/SA — see RoleTemplate.default_templates/0),
    # so the list has more than our one row and "BE" collides with the
    # unique_constraint([:organization_id, :abbreviation]). Use an
    # abbreviation outside the default set and look up our row by it.
    {:ok, _} =
      Estimate.Accounts.create_role_template(org.id, %{
        "name" => "QA Engineer",
        "abbreviation" => "QA"
      })

    assert {:reply, response, _} = ListRoleTemplates.execute(%{}, frame)
    assert %{"role_templates" => role_templates} = json_content(response)

    assert %{"name" => "QA Engineer", "abbreviation" => "QA", "rates" => _} =
             Enum.find(role_templates, &(&1["abbreviation"] == "QA"))
  end

  test "list_currencies returns org currencies", %{org: org, frame: frame} do
    # user_with_organization_fixture/0 auto-seeds 4 default currencies
    # (USD as main, EUR/GBP/PLN — see Currency.default_currencies/0), and a
    # partial unique index allows only one is_main row per org
    # (currencies_org_main_index), so "USD"/is_main: true would collide.
    # Add a second, non-main currency and check both it and the seeded
    # main currency serialize correctly.
    {:ok, _} =
      Estimate.Organizations.Currencies.create_currency(org.id, %{
        "code" => "CHF",
        "name" => "Swiss Franc",
        "symbol" => "CHF",
        "exchange_rate" => "0.9",
        "is_main" => false
      })

    assert {:reply, response, _} = ListCurrencies.execute(%{}, frame)
    assert %{"currencies" => currencies} = json_content(response)
    assert %{"code" => "USD", "is_main" => true} = Enum.find(currencies, &(&1["code"] == "USD"))
    assert %{"code" => "CHF", "is_main" => false} = Enum.find(currencies, &(&1["code"] == "CHF"))
  end
end
