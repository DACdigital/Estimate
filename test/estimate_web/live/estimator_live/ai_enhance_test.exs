defmodule EstimateWeb.EstimatorLive.AiEnhanceTest do
  use EstimateWeb.ConnCase, async: false

  require Logger
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
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
    # Same handshake as BlockingAI: tells the test which pid to monitor
    # before crashing, so the test can wait for that exact task's :DOWN
    # instead of sleeping.
    def enhance_description(_, _, _, _, _) do
      test_pid = :persistent_term.get(:ai_enhance_test_pid)
      send(test_pid, {:ai_stub_started, self()})
      raise "boom"
    end
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

    # `prev` is nil whenever the key was never configured (the common case) —
    # `put_env(.., nil)` would leave a stray `nil` entry instead of the
    # true "unset" state, so restore with delete_env in that case.
    on_exit(fn ->
      if is_nil(prev) do
        Application.delete_env(:estimate, :ai_enhancer)
      else
        Application.put_env(:estimate, :ai_enhancer, prev)
      end
    end)

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

    assert_receive {:ai_stub_started, stub_pid}, 1_000
    assert assigns(lv).ai_loading == "epic"

    send(stub_pid, :go)

    render_async(lv)
    assert_push_event(lv, "ai_set_description", %{text: "HELLO", target: "epic"})
    assert assigns(lv).ai_loading == nil
  end

  test "a crashing provider flashes AI request failed", ctx do
    :persistent_term.put(:ai_enhance_test_pid, self())
    Application.put_env(:estimate, :ai_enhancer, FailingAI)

    {:ok, lv, _} =
      live(
        ctx.conn,
        ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/estimations/#{ctx.est.id}/estimator"
      )

    render_click(lv, "add_epic", %{})

    # FailingAI raises inside the async Task started by `start_async`; that
    # crash report is expected (it's exactly what handle_async's {:exit, _}
    # clause is for) but should not pollute test output — capture it and
    # assert on its content instead.
    #
    # Task.Supervised logs the crash report *before* the task process
    # actually exits (the log call happens synchronously as the raised
    # exception unwinds, ahead of process termination), so waiting for the
    # task's own :DOWN guarantees the log call has already been made — no
    # sleep needed.
    {html, log} =
      with_log(fn ->
        render_click(lv, "ai_enhance_description", %{
          "description" => "hello",
          "name" => "E",
          "target" => "epic"
        })

        assert_receive {:ai_stub_started, stub_pid}, 1_000
        ref = Process.monitor(stub_pid)
        assert_receive {:DOWN, ^ref, :process, ^stub_pid, _}, 1_000

        html = render_async(lv)
        Logger.flush()
        html
      end)

    assert html =~ "AI request failed"
    assert log =~ "boom"
    assert assigns(lv).ai_loading == nil
  end

  test "ai_enhance_description without an org API key flashes AI not configured", %{conn: conn} do
    # a fresh org: the file's setup configures a key on ctx.org, this one never had one
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)

    {:ok, lv, _} =
      live(
        log_in_user(build_conn(), owner),
        ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{est.id}/estimator"
      )

    refute assigns(lv).ai_configured
    render_click(lv, "add_epic", %{})

    html =
      render_click(lv, "ai_enhance_description", %{
        "description" => "hello",
        "name" => "E",
        "target" => "epic"
      })

    assert html =~ "AI not configured"
    assert assigns(lv).ai_loading == nil
  end
end
