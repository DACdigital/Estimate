defmodule EstimateWeb.EstimatorLive.IndexAuthzTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.{Portfolio, Repo}
  alias Estimate.EstimationEngine.{Epic, Task}

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  defp estimator_path(org, project, estimation),
    do: ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"

  # member is EDITOR on project A and VIEWER on project B, both in the same org.
  # B's epic/task are visible to them (RLS allows collaborators) but must not be editable
  # from A's estimator.
  setup %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project_a = project_fixture(nil, owner)
    project_b = project_fixture(nil, owner)
    est_a = estimation_fixture(project_a)
    est_b = estimation_fixture(project_b)
    epic_b = epic_fixture(est_b, %{name: "B-EPIC"})
    task_b = task_fixture(epic_b, %{name: "B-TASK"})

    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    {:ok, _} = Portfolio.add_collaborator(project_a.id, member.id, "editor")
    {:ok, _} = Portfolio.add_collaborator(project_b.id, member.id, "viewer")

    viewer = user_fixture()
    _ = membership_fixture(viewer, org, "member")
    {:ok, _} = Portfolio.add_collaborator(project_a.id, viewer.id, "viewer")

    {:ok, lv, _} = live(log_in_user(conn, member), estimator_path(org, project_a, est_a))

    %{
      conn: conn,
      org: org,
      project_a: project_a,
      est_a: est_a,
      epic_b: epic_b,
      task_b: task_b,
      member: member,
      viewer: viewer,
      lv: lv
    }
  end

  describe "foreign estimation ids are rejected in memory" do
    test "confirm_delete_epic + delete_epic", %{lv: lv, epic_b: epic_b} do
      render_click(lv, "confirm_delete_epic", %{"id" => epic_b.id})
      assert assigns(lv).deleting_epic == nil
      assert render(lv) =~ "Not found"

      render_click(lv, "delete_epic", %{})
      assert Repo.get(Epic, epic_b.id)
    end

    test "edit_epic + save_epic", %{lv: lv, epic_b: epic_b} do
      render_click(lv, "edit_epic", %{"id" => epic_b.id})
      assert assigns(lv).epic_form == nil
      assert render(lv) =~ "Not found"

      assert Repo.get!(Epic, epic_b.id).name == "B-EPIC"
    end

    test "add_task into foreign epic", %{lv: lv, epic_b: epic_b} do
      render_click(lv, "add_task", %{"epic-id" => epic_b.id})
      assert assigns(lv).current_epic_id == nil
      assert render(lv) =~ "Not found"

      render_submit(lv, "save_task", %{"task" => %{"name" => "INJECTED"}})
      refute Repo.get_by(Task, epic_id: epic_b.id, name: "INJECTED")
    end

    test "edit_task + confirm_delete_task + delete_task", %{lv: lv, task_b: task_b} do
      render_click(lv, "edit_task", %{"id" => task_b.id})
      assert assigns(lv).task_form == nil

      render_click(lv, "confirm_delete_task", %{"id" => task_b.id})
      assert assigns(lv).deleting_task == nil

      render_click(lv, "delete_task", %{})
      assert Repo.get(Task, task_b.id)
    end
  end

  describe "nil-form guards (no modal open)" do
    test "save_epic with no modal open does not crash the LV", %{lv: lv} do
      assert assigns(lv).epic_form == nil

      render_submit(lv, "save_epic", %{"epic" => %{"name" => "INJECTED"}})

      assert Process.alive?(lv.pid)
      assert render(lv) =~ "Not found"
      refute Repo.get_by(Epic, name: "INJECTED")
    end

    test "validate_task with no modal open does not crash the LV", %{lv: lv} do
      assert assigns(lv).task_form == nil

      render_change(lv, "validate_task", %{"task" => %{"name" => "x"}})

      assert Process.alive?(lv.pid)
      assert render(lv) =~ "Not found"
    end
  end

  describe "own estimation still works" do
    test "confirm_delete_epic on own epic sets the assign", %{lv: lv, est_a: est_a} do
      epic_a = epic_fixture(est_a, %{name: "A-EPIC"})
      # LV loaded before the epic existed: reload via the PubSub path the LV listens on
      send(lv.pid, {:epic_created, epic_a})
      render(lv)

      render_click(lv, "confirm_delete_epic", %{"id" => epic_a.id})
      assert assigns(lv).deleting_epic.id == epic_a.id
    end

    test "edit_epic on own epic populates the form", %{lv: lv, est_a: est_a} do
      epic_a = epic_fixture(est_a, %{name: "A-EPIC"})
      send(lv.pid, {:epic_created, epic_a})
      render(lv)

      render_click(lv, "edit_epic", %{"id" => epic_a.id})
      assert assigns(lv).modal == :epic
      assert assigns(lv).epic_form.data.id == epic_a.id
    end

    test "add_task on own epic opens the form and save_task creates the row",
         %{lv: lv, est_a: est_a} do
      epic_a = epic_fixture(est_a, %{name: "A-EPIC"})
      send(lv.pid, {:epic_created, epic_a})
      render(lv)

      render_click(lv, "add_task", %{"epic-id" => epic_a.id})
      assert assigns(lv).modal == :task
      assert assigns(lv).current_epic_id == epic_a.id

      render_submit(lv, "save_task", %{"task" => %{"name" => "NEW"}})
      assert Repo.get_by(Task, epic_id: epic_a.id, name: "NEW")
    end

    test "edit_task on own task populates the form", %{lv: lv, est_a: est_a} do
      epic_a = epic_fixture(est_a, %{name: "A-EPIC"})
      send(lv.pid, {:epic_created, epic_a})
      render(lv)

      task_a = task_fixture(epic_a, %{name: "A-TASK"})
      send(lv.pid, {:task_created, task_a})
      render(lv)

      render_click(lv, "edit_task", %{"id" => task_a.id})
      assert assigns(lv).modal == :task
      assert assigns(lv).task_form.data.id == task_a.id
      assert assigns(lv).current_epic_id == epic_a.id
    end
  end

  describe "viewer on this project" do
    setup %{conn: conn, org: org, project_a: project_a, est_a: est_a, viewer: viewer} do
      epic_a = epic_fixture(est_a, %{name: "A-EPIC"})
      {:ok, lv, _} = live(log_in_user(conn, viewer), estimator_path(org, project_a, est_a))
      %{vlv: lv, epic_a: epic_a}
    end

    test "confirm_delete_epic is denied", %{vlv: lv, epic_a: epic_a} do
      render_click(lv, "confirm_delete_epic", %{"id" => epic_a.id})
      assert assigns(lv).deleting_epic == nil
      assert render(lv) =~ "You don&#39;t have edit access"
    end

    test "ai_enhance_description is denied", %{vlv: lv} do
      render_click(lv, "ai_enhance_description", %{
        "description" => "x",
        "name" => "y",
        "target" => "epic"
      })

      assert assigns(lv).ai_loading == nil
      assert render(lv) =~ "You don&#39;t have edit access"
    end
  end
end
