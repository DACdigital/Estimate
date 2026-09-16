defmodule EstimateWeb.EstimatorLive.AiEnhanceTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  defmodule BlockingAI do
    # The test registers itself under :ai_enhance_test_pid; the stub tells the test it
    # started, then waits for :go. No timing assumptions anywhere.
    def enhance_description(_key, _model, _prompt, _name, desc) do
      test_pid = :persistent_term.get(:ai_enhance_test_pid)
      send(test_pid, {:ai_stub_started, self()})

      receive do
        :go -> {:ok, String.upcase(desc)}
      end
    end
  end

  defmodule FailingAI do
    def enhance_description(_, _, _, _, _), do: raise("boom")
  end

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  setup %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()

    {:ok, org} =
      Estimate.Organizations.update_ai_settings(org, %{
        "openrouter_api_key" => "sk-or-test-key-123456"
      })

    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    prev = Application.get_env(:estimate, :ai_enhancer)
    on_exit(fn -> Application.put_env(:estimate, :ai_enhancer, prev) end)
    on_exit(fn -> :persistent_term.erase(:ai_enhance_test_pid) end)
    %{conn: log_in_user(conn, owner), org: org, project: project, est: est}
  end

  test "result arrives via handle_async and clears loading", ctx do
    :persistent_term.put(:ai_enhance_test_pid, self())
    Application.put_env(:estimate, :ai_enhancer, BlockingAI)

    {:ok, lv, _} =
      live(
        ctx.conn,
        ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/estimations/#{ctx.est.id}/estimator"
      )

    render_click(lv, "add_epic", %{})

    render_click(lv, "ai_enhance_description", %{
      "description" => "hello",
      "name" => "E",
      "target" => "epic"
    })

    assert_receive {:ai_stub_started, stub_pid}
    assert assigns(lv).ai_loading == "epic"

    send(stub_pid, :go)

    render_async(lv)
    assert_push_event(lv, "ai_set_description", %{text: "HELLO", target: "epic"})
    assert assigns(lv).ai_loading == nil
  end

  test "a crashing provider flashes AI request failed", ctx do
    Application.put_env(:estimate, :ai_enhancer, FailingAI)

    {:ok, lv, _} =
      live(
        ctx.conn,
        ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/estimations/#{ctx.est.id}/estimator"
      )

    render_click(lv, "add_epic", %{})

    render_click(lv, "ai_enhance_description", %{
      "description" => "hello",
      "name" => "E",
      "target" => "epic"
    })

    html = render_async(lv)
    assert html =~ "AI request failed"
    assert assigns(lv).ai_loading == nil
  end
end
