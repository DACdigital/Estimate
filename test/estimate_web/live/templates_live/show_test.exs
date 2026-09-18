defmodule EstimateWeb.TemplatesLive.ShowTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
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

    test "an invalid name is silently ignored (characterizes today: no flash)", ctx do
      html = render_change(ctx.lv, "update_template", %{"name" => "", "description" => "x"})
      refute html =~ "Could not save template"
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

    test "member can open the epic modal and stage a delete (characterizes today's gap; changed in B3)",
         ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      render_click(lv, "add_epic", %{})
      assert assigns(lv).modal == :epic
      render_click(lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      assert assigns(lv).deleting_epic.id == ctx.epic.id
    end

    test "member is denied on save_epic, delete_epic and reorder_epics", ctx do
      {:ok, lv, _} = mount_as_member(ctx)

      assert render_submit(lv, "save_epic", %{"epic_id" => "", "name" => "X", "description" => ""}) =~
               "Not authorized"

      render_click(lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      assert render_click(lv, "delete_epic", %{}) =~ "Not authorized"
      assert render_click(lv, "reorder_epics", %{"ids" => [ctx.epic.id]}) =~ "Not authorized"
      assert Repo.get(EstimationTemplateEpic, ctx.epic.id)
      assert length(refetch(ctx.template, ctx.org).epics) == 1
    end

    test "edit_epic with an unknown id crashes the LiveView (characterizes today's gap; changed in B3)",
         ctx do
      Process.flag(:trap_exit, true)

      log =
        capture_log(fn ->
          try do
            render_click(ctx.lv, "edit_epic", %{"id" => Ecto.UUID.generate()})
          catch
            :exit, _reason -> :ok
          end
        end)

      assert log =~ "BadMapError"
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

    test "member can open the task modal and stage a delete (characterizes today's gap; changed in B3)",
         ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      render_click(lv, "add_task", %{"epic-id" => ctx.epic.id})
      assert assigns(lv).modal == :task
      render_click(lv, "confirm_delete_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})
      assert assigns(lv).deleting_task.id == ctx.task1.id
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

    test "edit_task with an unknown epic id crashes the LiveView (characterizes today's gap; changed in B3)",
         ctx do
      Process.flag(:trap_exit, true)

      log =
        capture_log(fn ->
          try do
            render_click(ctx.lv, "edit_task", %{
              "id" => ctx.task1.id,
              "epic-id" => Ecto.UUID.generate()
            })
          catch
            :exit, _reason -> :ok
          end
        end)

      assert log =~ "BadMapError"
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
end
