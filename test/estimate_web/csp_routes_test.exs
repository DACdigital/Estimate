defmodule EstimateWeb.CspRoutesTest do
  use EstimateWeb.ConnCase, async: true
  import Estimate.{CRMFixtures, PortfolioFixtures, EstimationEngineFixtures, TemplatesFixtures}

  setup :register_and_log_in_org_owner

  test "no inline script without the request nonce on any org page", %{
    conn: conn,
    org: org,
    user: user
  } do
    customer = customer_fixture(org)
    project = project_fixture(nil, user)
    estimation = estimation_fixture(project)
    template = template_fixture(org)

    paths = [
      ~p"/organizations",
      ~p"/account",
      ~p"/account/two-factor/setup",
      ~p"/org/#{org.id}",
      ~p"/org/#{org.id}/roles",
      ~p"/org/#{org.id}/templates",
      ~p"/org/#{org.id}/templates/#{template.id}",
      ~p"/org/#{org.id}/settings",
      ~p"/org/#{org.id}/settings/members",
      ~p"/org/#{org.id}/settings/currencies",
      ~p"/org/#{org.id}/settings/ai",
      ~p"/org/#{org.id}/settings/email",
      ~p"/org/#{org.id}/settings/mcp",
      ~p"/org/#{org.id}/settings/trash",
      ~p"/org/#{org.id}/customers",
      ~p"/org/#{org.id}/customers/#{customer.id}",
      ~p"/org/#{org.id}/projects",
      ~p"/org/#{org.id}/projects/#{project.id}",
      ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"
    ]

    for path <- paths do
      resp = get(conn, path)
      assert resp.status == 200, "#{path} -> #{resp.status}"
      [header] = get_resp_header(resp, "content-security-policy")
      [nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, header, capture: :all_but_first)
      html = resp.resp_body

      inline_scripts = Regex.scan(~r/<script(?![^>]*\bsrc=)[^>]*>/, html) |> List.flatten()

      for tag <- inline_scripts do
        assert tag =~ ~s(nonce="#{nonce}"), "#{path}: inline script without nonce: #{tag}"
      end
    end
  end
end
