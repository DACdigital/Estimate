defmodule EstimateWeb.TemplatesLiveHelpers do
  @moduledoc """
  Shared setup for TemplatesLive.Show characterization tests: org + owner, one
  template with one epic ("Alpha") and two tasks ("T-one", "T-two"), mounted
  as the owner.
  """
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  import Estimate.{AccountsFixtures, TemplatesFixtures}

  alias Estimate.Templates

  @endpoint EstimateWeb.Endpoint

  def assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  def template_path(org, template), do: "/org/#{org.id}/templates/#{template.id}"

  def refetch(template, org), do: Templates.get_estimation_template!(template.id, org.id)

  def setup_template(%{conn: conn}) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    template = template_fixture(org, %{name: "Tpl", description: "Desc"})

    {:ok, epic} =
      Templates.create_template_epic(%{
        "name" => "Alpha",
        "position" => 0,
        "estimation_template_id" => template.id
      })

    {:ok, task1} =
      Templates.create_template_task(%{
        "name" => "T-one",
        "position" => 0,
        "priority" => "must",
        "estimation_template_epic_id" => epic.id
      })

    {:ok, task2} =
      Templates.create_template_task(%{
        "name" => "T-two",
        "position" => 1,
        "priority" => "should",
        "estimation_template_epic_id" => epic.id
      })

    template = refetch(template, org)
    conn = EstimateWeb.ConnCase.log_in_user(conn, owner)
    {:ok, lv, _html} = live(conn, template_path(org, template))

    %{
      conn: conn,
      org: org,
      owner: owner,
      template: template,
      epic: epic,
      task1: task1,
      task2: task2,
      lv: lv
    }
  end

  @doc "Mounts the same template as a fresh non-admin org member."
  def mount_as_member(%{org: org, template: template}) do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    live(EstimateWeb.ConnCase.log_in_user(build_conn(), member), template_path(org, template))
  end
end
