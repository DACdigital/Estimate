defmodule EstimateWeb.TemplatesLive.ShowTest do
  use EstimateWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import EstimateWeb.TemplatesLiveHelpers

  alias Estimate.Repo
  alias Estimate.Templates.{EstimationTemplate, EstimationTemplateEpic, EstimationTemplateTask}

  setup :setup_template

  describe "mount" do
    test "owner mounts with is_admin and default view state", ctx do
      a = assigns(ctx.lv)
      assert a.is_admin
      assert a.template.id == ctx.template.id
      assert a.page_title == "Tpl"
      assert a.active_tab == :templates
      assert a.modal == nil and a.current_epic_id == nil and a.current_task_id == nil
      assert a.deleting_epic == nil and a.deleting_task == nil
      html = render(ctx.lv)
      assert html =~ "Alpha" and html =~ "T-one" and html =~ "T-two"
      assert html =~ ~s(phx-change="update_template")
    end

    test "member mounts read-only", ctx do
      {:ok, lv, html} = mount_as_member(ctx)
      refute assigns(lv).is_admin
      refute html =~ ~s(phx-change="update_template")
      refute html =~ ~s(phx-click="add_epic")
    end
  end

  describe "update_template" do
    test "renames and re-describes the template", ctx do
      render_change(ctx.lv, "update_template", %{"name" => "Renamed", "description" => "New"})
      assert assigns(ctx.lv).template.name == "Renamed"
      assert Repo.get!(EstimationTemplate, ctx.template.id).description == "New"
    end

    test "an invalid name flashes Could not save template (B3)", ctx do
      html = render_change(ctx.lv, "update_template", %{"name" => "", "description" => "x"})
      assert html =~ "Could not save template"
      assert Repo.get!(EstimationTemplate, ctx.template.id).name == "Tpl"
    end

    test "member is denied", ctx do
      {:ok, lv, _} = mount_as_member(ctx)

      assert render_change(lv, "update_template", %{"name" => "Hijack", "description" => ""}) =~
               "Not authorized"

      assert Repo.get!(EstimationTemplate, ctx.template.id).name == "Tpl"
    end
  end

  describe "epics" do
    test "add_epic opens an empty epic modal", ctx do
      render_click(ctx.lv, "add_epic", %{})
      a = assigns(ctx.lv)
      assert a.modal == :epic and a.current_epic_id == nil
      assert a.epic_form[:name].value == ""
      assert render(ctx.lv) =~ ~s(id="epic-modal")
    end

    test "edit_epic opens the modal prefilled", ctx do
      render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})
      a = assigns(ctx.lv)
      assert a.modal == :epic and a.current_epic_id == ctx.epic.id
      assert a.epic_form[:name].value == "Alpha"
    end

    test "save_epic with an empty epic_id creates at the next position and closes", ctx do
      render_click(ctx.lv, "add_epic", %{})

      render_submit(ctx.lv, "save_epic", %{"epic_id" => "", "name" => "Beta", "description" => ""})

      a = assigns(ctx.lv)
      assert a.modal == nil
      assert Enum.map(a.template.epics, &{&1.name, &1.position}) == [{"Alpha", 0}, {"Beta", 1}]
    end

    test "save_epic with an epic_id updates and closes", ctx do
      render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})

      render_submit(ctx.lv, "save_epic", %{
        "epic_id" => ctx.epic.id,
        "name" => "Alpha-2",
        "description" => "d"
      })

      assert assigns(ctx.lv).modal == nil
      assert Repo.get!(EstimationTemplateEpic, ctx.epic.id).name == "Alpha-2"
    end

    test "save_epic with an empty name flashes and keeps the modal", ctx do
      render_click(ctx.lv, "add_epic", %{})

      html =
        render_submit(ctx.lv, "save_epic", %{"epic_id" => "", "name" => "", "description" => ""})

      assert html =~ "Could not create epic"
      assert assigns(ctx.lv).modal == :epic
    end

    test "confirm_delete_epic / cancel_delete toggle deleting_epic", ctx do
      render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      assert assigns(ctx.lv).deleting_epic.id == ctx.epic.id
      assert render(ctx.lv) =~ ~s(id="delete-epic-modal")
      render_click(ctx.lv, "cancel_delete", %{})
      assert assigns(ctx.lv).deleting_epic == nil
    end

    test "delete_epic deletes the confirmed epic and its tasks", ctx do
      render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      html = render_click(ctx.lv, "delete_epic", %{})
      assert html =~ "Epic deleted"
      assert assigns(ctx.lv).deleting_epic == nil
      assert assigns(ctx.lv).template.epics == []
      refute Repo.get(EstimationTemplateEpic, ctx.epic.id)
      refute Repo.get(EstimationTemplateTask, ctx.task1.id)
    end

    test "reorder_epics applies the new order", ctx do
      render_click(ctx.lv, "add_epic", %{})

      render_submit(ctx.lv, "save_epic", %{"epic_id" => "", "name" => "Beta", "description" => ""})

      [alpha, beta] = assigns(ctx.lv).template.epics
      render_click(ctx.lv, "reorder_epics", %{"ids" => [beta.id, alpha.id]})
      assert Enum.map(assigns(ctx.lv).template.epics, & &1.name) == ["Beta", "Alpha"]
    end

    test "member is denied on add_epic, edit_epic and confirm_delete_epic (B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      assert render_click(lv, "add_epic", %{}) =~ "Not authorized"
      assert render_click(lv, "edit_epic", %{"id" => ctx.epic.id}) =~ "Not authorized"
      assert render_click(lv, "confirm_delete_epic", %{"id" => ctx.epic.id}) =~ "Not authorized"
      a = assigns(lv)
      assert a.modal == nil and a.deleting_epic == nil
    end

    test "member is denied on save_epic, delete_epic and reorder_epics", ctx do
      render_click(ctx.lv, "add_epic", %{})

      render_submit(ctx.lv, "save_epic", %{
        "epic_id" => "",
        "name" => "Beta",
        "description" => ""
      })

      [alpha, beta] = assigns(ctx.lv).template.epics

      {:ok, lv, _} = mount_as_member(ctx)

      assert render_submit(lv, "save_epic", %{"epic_id" => "", "name" => "X", "description" => ""}) =~
               "Not authorized"

      render_click(lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      assert render_click(lv, "delete_epic", %{}) =~ "Not authorized"

      assert render_click(lv, "reorder_epics", %{"ids" => [beta.id, alpha.id]}) =~
               "Not authorized"

      assert Repo.get(EstimationTemplateEpic, ctx.epic.id)
      assert Enum.map(refetch(ctx.template, ctx.org).epics, & &1.name) == ["Alpha", "Beta"]
    end

    test "edit_epic / confirm_delete_epic with an unknown id flash Not found (B3)", ctx do
      assert render_click(ctx.lv, "edit_epic", %{"id" => Ecto.UUID.generate()}) =~ "Not found"
      assert assigns(ctx.lv).modal == nil

      assert render_click(ctx.lv, "confirm_delete_epic", %{"id" => Ecto.UUID.generate()}) =~
               "Not found"

      assert assigns(ctx.lv).deleting_epic == nil
      assert Process.alive?(ctx.lv.pid)
    end

    test "member is denied on save_epic update (B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)

      assert render_submit(lv, "save_epic", %{
               "epic_id" => ctx.epic.id,
               "name" => "Hijack",
               "description" => ""
             }) =~ "Not authorized"

      assert Repo.get!(EstimationTemplateEpic, ctx.epic.id).name == "Alpha"
    end

    test "save_epic update with an unknown epic_id flashes Not found and keeps the modal open",
         ctx do
      render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})

      html =
        render_submit(ctx.lv, "save_epic", %{
          "epic_id" => Ecto.UUID.generate(),
          "name" => "X",
          "description" => ""
        })

      assert html =~ "Not found"
      assert assigns(ctx.lv).modal == :epic
      assert Process.alive?(ctx.lv.pid)
    end
  end

  describe "tasks" do
    test "add_task opens the task modal bound to the epic", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
      a = assigns(ctx.lv)
      assert a.modal == :task and a.current_epic_id == ctx.epic.id and a.current_task_id == nil
      assert a.task_form[:priority].value == "must"
      assert render(ctx.lv) =~ ~s(id="task-modal")
    end

    test "edit_task opens the modal prefilled", ctx do
      render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id, "epic-id" => ctx.epic.id})
      a = assigns(ctx.lv)
      assert a.modal == :task and a.current_task_id == ctx.task2.id
      assert a.task_form[:name].value == "T-two" and a.task_form[:priority].value == "should"
    end

    test "save_task with an empty task_id creates at the next position and closes", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})

      render_submit(ctx.lv, "save_task", %{
        "task_id" => "",
        "epic_id" => ctx.epic.id,
        "name" => "T-three",
        "description" => "",
        "priority" => "could"
      })

      a = assigns(ctx.lv)
      assert a.modal == nil
      [epic] = a.template.epics

      assert Enum.map(epic.tasks, &{&1.name, &1.position, &1.priority}) == [
               {"T-one", 0, "must"},
               {"T-two", 1, "should"},
               {"T-three", 2, "could"}
             ]
    end

    test "save_task with a task_id updates and closes", ctx do
      render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})

      render_submit(ctx.lv, "save_task", %{
        "task_id" => ctx.task1.id,
        "epic_id" => ctx.epic.id,
        "name" => "T-one-2",
        "description" => "",
        "priority" => "wont"
      })

      assert assigns(ctx.lv).modal == nil
      t = Repo.get!(EstimationTemplateTask, ctx.task1.id)
      assert t.name == "T-one-2" and t.priority == "wont"
    end

    test "save_task with an empty name flashes and keeps the modal", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})

      html =
        render_submit(ctx.lv, "save_task", %{
          "task_id" => "",
          "epic_id" => ctx.epic.id,
          "name" => "",
          "description" => "",
          "priority" => "must"
        })

      assert html =~ "Could not create task"
      assert assigns(ctx.lv).modal == :task
    end

    test "confirm_delete_task / cancel_delete toggle deleting_task", ctx do
      render_click(ctx.lv, "confirm_delete_task", %{
        "id" => ctx.task2.id,
        "epic-id" => ctx.epic.id
      })

      assert assigns(ctx.lv).deleting_task.id == ctx.task2.id
      assert render(ctx.lv) =~ ~s(id="delete-task-modal")
      render_click(ctx.lv, "cancel_delete", %{})
      assert assigns(ctx.lv).deleting_task == nil
    end

    test "delete_task deletes the confirmed task", ctx do
      render_click(ctx.lv, "confirm_delete_task", %{
        "id" => ctx.task2.id,
        "epic-id" => ctx.epic.id
      })

      html = render_click(ctx.lv, "delete_task", %{})
      assert html =~ "Task deleted"
      assert assigns(ctx.lv).deleting_task == nil
      refute Repo.get(EstimationTemplateTask, ctx.task2.id)
    end

    test "reorder_tasks applies the new order within the epic", ctx do
      render_click(ctx.lv, "reorder_tasks", %{
        "epic_id" => ctx.epic.id,
        "ids" => [ctx.task2.id, ctx.task1.id]
      })

      [epic] = assigns(ctx.lv).template.epics
      assert Enum.map(epic.tasks, & &1.name) == ["T-two", "T-one"]
    end

    test "member is denied on add_task, edit_task and confirm_delete_task (B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      assert render_click(lv, "add_task", %{"epic-id" => ctx.epic.id}) =~ "Not authorized"

      assert render_click(lv, "edit_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id}) =~
               "Not authorized"

      assert render_click(lv, "confirm_delete_task", %{
               "id" => ctx.task1.id,
               "epic-id" => ctx.epic.id
             }) =~ "Not authorized"

      a = assigns(lv)
      assert a.modal == nil and a.deleting_task == nil
    end

    test "member is denied on save_task, delete_task and reorder_tasks", ctx do
      {:ok, lv, _} = mount_as_member(ctx)

      assert render_submit(lv, "save_task", %{
               "task_id" => "",
               "epic_id" => ctx.epic.id,
               "name" => "X",
               "description" => "",
               "priority" => "must"
             }) =~ "Not authorized"

      render_click(lv, "confirm_delete_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})
      assert render_click(lv, "delete_task", %{}) =~ "Not authorized"

      assert render_click(lv, "reorder_tasks", %{
               "epic_id" => ctx.epic.id,
               "ids" => [ctx.task2.id, ctx.task1.id]
             }) =~ "Not authorized"

      assert Repo.get(EstimationTemplateTask, ctx.task1.id)
      [epic] = refetch(ctx.template, ctx.org).epics
      assert Enum.map(epic.tasks, & &1.name) == ["T-one", "T-two"]
    end

    test "edit_task / confirm_delete_task with an unknown epic or task id flash Not found (B3)",
         ctx do
      assert render_click(ctx.lv, "edit_task", %{
               "id" => ctx.task1.id,
               "epic-id" => Ecto.UUID.generate()
             }) =~ "Not found"

      assert render_click(ctx.lv, "edit_task", %{
               "id" => Ecto.UUID.generate(),
               "epic-id" => ctx.epic.id
             }) =~ "Not found"

      assert assigns(ctx.lv).modal == nil

      assert render_click(ctx.lv, "confirm_delete_task", %{
               "id" => Ecto.UUID.generate(),
               "epic-id" => ctx.epic.id
             }) =~ "Not found"

      assert assigns(ctx.lv).deleting_task == nil
      assert Process.alive?(ctx.lv.pid)
    end

    test "reorder_tasks for an epic that is not in this template is rejected (B3)", ctx do
      other = Estimate.TemplatesFixtures.template_fixture(ctx.org)

      {:ok, other_epic} =
        Estimate.Templates.create_template_epic(%{
          "name" => "Other",
          "position" => 0,
          "estimation_template_id" => other.id
        })

      {:ok, ot} =
        Estimate.Templates.create_template_task(%{
          "name" => "OT",
          "position" => 0,
          "estimation_template_epic_id" => other_epic.id
        })

      assert render_click(ctx.lv, "reorder_tasks", %{"epic_id" => other_epic.id, "ids" => [ot.id]}) =~
               "Not found"

      assert Repo.get!(EstimationTemplateTask, ot.id).position == 0
    end

    test "member is denied on save_task update (B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)

      assert render_submit(lv, "save_task", %{
               "task_id" => ctx.task1.id,
               "epic_id" => ctx.epic.id,
               "name" => "Hijack",
               "description" => "",
               "priority" => "must"
             }) =~ "Not authorized"

      assert Repo.get!(EstimationTemplateTask, ctx.task1.id).name == "T-one"
    end

    test "save_task update with an unknown task_id flashes Not found and keeps the modal open",
         ctx do
      render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})

      html =
        render_submit(ctx.lv, "save_task", %{
          "task_id" => Ecto.UUID.generate(),
          "epic_id" => ctx.epic.id,
          "name" => "X",
          "description" => "",
          "priority" => "must"
        })

      assert html =~ "Not found"
      assert assigns(ctx.lv).modal == :task
      assert Process.alive?(ctx.lv.pid)
    end

    test "save_task create is rejected for an epic belonging to another template (B3)", ctx do
      other = Estimate.TemplatesFixtures.template_fixture(ctx.org)

      {:ok, other_epic} =
        Estimate.Templates.create_template_epic(%{
          "name" => "Other",
          "position" => 0,
          "estimation_template_id" => other.id
        })

      html =
        render_submit(ctx.lv, "save_task", %{
          "task_id" => "",
          "epic_id" => other_epic.id,
          "name" => "Sneak",
          "description" => "",
          "priority" => "must"
        })

      assert html =~ "Not found"

      assert Repo.all(
               from(t in EstimationTemplateTask,
                 where: t.estimation_template_epic_id == ^other_epic.id
               )
             ) == []
    end

    test "add_task with an unknown epic id flashes Not found and does not open the modal (B3)",
         ctx do
      assert render_click(ctx.lv, "add_task", %{"epic-id" => Ecto.UUID.generate()}) =~
               "Not found"

      assert assigns(ctx.lv).modal == nil
    end
  end

  describe "modal / delete housekeeping" do
    test "close_modal clears only the modal", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
      assert assigns(ctx.lv).modal == :task
      render_click(ctx.lv, "close_modal", %{})
      a = assigns(ctx.lv)
      assert a.modal == nil
      # characterizes today: close_modal leaves current_epic_id as it was
      assert a.current_epic_id == ctx.epic.id
    end

    test "cancel_delete clears both deleting assigns", ctx do
      render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})

      render_click(ctx.lv, "confirm_delete_task", %{
        "id" => ctx.task1.id,
        "epic-id" => ctx.epic.id
      })

      a = assigns(ctx.lv)
      assert a.deleting_epic != nil and a.deleting_task != nil
      render_click(ctx.lv, "cancel_delete", %{})
      a = assigns(ctx.lv)
      assert a.deleting_epic == nil and a.deleting_task == nil
    end
  end

  describe "no client payload crashes the LiveView (4C)" do
    test "delete_epic with nothing confirmed flashes Not found", ctx do
      assert assigns(ctx.lv).deleting_epic == nil
      assert render_click(ctx.lv, "delete_epic", %{}) =~ "Not found"
      assert Process.alive?(ctx.lv.pid)
      assert length(refetch(ctx.template, ctx.org).epics) == 1
    end

    test "delete_task with nothing confirmed flashes Not found", ctx do
      assert assigns(ctx.lv).deleting_task == nil
      assert render_click(ctx.lv, "delete_task", %{}) =~ "Not found"
      assert Process.alive?(ctx.lv.pid)
      [epic] = refetch(ctx.template, ctx.org).epics
      assert length(epic.tasks) == 2
    end

    test "add_task without an epic-id flashes Not found", ctx do
      assert render_click(ctx.lv, "add_task", %{}) =~ "Not found"
      assert assigns(ctx.lv).modal == nil
      assert Process.alive?(ctx.lv.pid)
    end
  end
end
