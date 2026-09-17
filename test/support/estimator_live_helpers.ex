defmodule EstimateWeb.EstimatorLiveHelpers do
  @moduledoc """
  Shared setup for EstimatorLive characterization tests.

  `setup_estimator/1` builds: org + owner, one project, one estimation with
  the default roles, one epic with two tasks, and mounts the estimator as
  the owner. Returns everything a test needs to drive handlers directly.
  """
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine

  @endpoint EstimateWeb.Endpoint

  def assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  def estimator_path(org, project, estimation),
    do: "/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"

  @doc "Re-reads the estimation with roles/epics/tasks/estimates preloaded."
  def refetch(estimation, org), do: EstimationEngine.get_estimation!(estimation.id, org.id)

  def setup_estimator(%{conn: conn}) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    epic = epic_fixture(est, %{name: "Alpha"})
    # NOTE: characterizes current behaviour; see report. Epic/Task position defaults
    # to 0 (see Epic.changeset/2, Task.changeset/2) and the LV's add_epic/add_task
    # handlers never auto-increment it on create, so two same-position siblings sort
    # in whatever order Postgres's `order_by: position` scan happens to return them -
    # stable in isolation but observed to flip under this suite's concurrent DB load.
    # Assigning explicit positions here keeps every downstream test deterministic.
    task1 = task_fixture(epic, %{name: "T-one", position: 0})
    task2 = task_fixture(epic, %{name: "T-two", position: 1})
    est = refetch(est, org)

    conn = EstimateWeb.ConnCase.log_in_user(conn, owner)
    {:ok, lv, _html} = live(conn, estimator_path(org, project, est))

    %{
      conn: conn,
      org: org,
      owner: owner,
      project: project,
      est: est,
      epic: epic,
      task1: task1,
      task2: task2,
      role: hd(est.roles),
      lv: lv
    }
  end

  @doc "A second project/estimation in the same org, owned by `owner`; returns preloaded estimation."
  def other_estimation(owner, org) do
    other_project = project_fixture(nil, owner)
    other_estimation = estimation_fixture(other_project)
    other_epic = epic_fixture(other_estimation, %{name: "Other-Epic"})
    other_task = task_fixture(other_epic, %{name: "Other-Task"})
    %{estimation: refetch(other_estimation, org), epic: other_epic, task: other_task}
  end

  @doc "Mounts the same estimator as a fresh org member with the given collaborator role (or no collaborator row when role is nil)."
  def mount_as(role, %{org: org, project: project, est: est}) do
    user = user_fixture()
    _ = membership_fixture(user, org, "member")
    if role, do: {:ok, _} = Estimate.Portfolio.add_collaborator(project.id, user.id, role)
    conn = EstimateWeb.ConnCase.log_in_user(build_conn(), user)
    {user, live(conn, estimator_path(org, project, est))}
  end
end
