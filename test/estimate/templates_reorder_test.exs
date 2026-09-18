defmodule Estimate.TemplatesReorderTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, TemplatesFixtures}
  alias Estimate.Templates

  setup do
    org = organization_fixture()
    template = template_fixture(org)

    {:ok, e1} =
      Templates.create_template_epic(%{
        "name" => "E1",
        "position" => 0,
        "estimation_template_id" => template.id
      })

    {:ok, e2} =
      Templates.create_template_epic(%{
        "name" => "E2",
        "position" => 1,
        "estimation_template_id" => template.id
      })

    {:ok, t1} =
      Templates.create_template_task(%{
        "name" => "T1",
        "position" => 0,
        "estimation_template_epic_id" => e1.id
      })

    {:ok, t2} =
      Templates.create_template_task(%{
        "name" => "T2",
        "position" => 1,
        "estimation_template_epic_id" => e1.id
      })

    %{org: org, template: template, e1: e1, e2: e2, t1: t1, t2: t2}
  end

  defp epic_ids(template, org),
    do: Templates.get_estimation_template!(template.id, org.id).epics |> Enum.map(& &1.id)

  defp task_ids(template, org, epic_id) do
    Templates.get_estimation_template!(template.id, org.id).epics
    |> Enum.find(&(&1.id == epic_id))
    |> Map.fetch!(:tasks)
    |> Enum.map(& &1.id)
  end

  test "reorder_template_epics/2 applies the order", ctx do
    assert :ok = Templates.reorder_template_epics(ctx.template.id, [ctx.e2.id, ctx.e1.id])
    assert epic_ids(ctx.template, ctx.org) == [ctx.e2.id, ctx.e1.id]
  end

  test "reorder_template_epics/2 rejects a stale (partial) id list untouched", ctx do
    assert {:error, :stale_reorder} =
             Templates.reorder_template_epics(ctx.template.id, [ctx.e2.id])

    assert epic_ids(ctx.template, ctx.org) == [ctx.e1.id, ctx.e2.id]
  end

  test "reorder_template_tasks/2 applies the order", ctx do
    assert :ok = Templates.reorder_template_tasks(ctx.e1.id, [ctx.t2.id, ctx.t1.id])
    assert task_ids(ctx.template, ctx.org, ctx.e1.id) == [ctx.t2.id, ctx.t1.id]
  end

  test "reorder_template_tasks/2 rejects a stale (partial) id list untouched", ctx do
    assert {:error, :stale_reorder} = Templates.reorder_template_tasks(ctx.e1.id, [ctx.t1.id])
    assert task_ids(ctx.template, ctx.org, ctx.e1.id) == [ctx.t1.id, ctx.t2.id]
  end
end
