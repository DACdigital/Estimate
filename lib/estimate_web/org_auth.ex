defmodule EstimateWeb.OrgAuth do
  @moduledoc """
  LiveView on_mount hook for organization-scoped routes.

  Verifies user membership and assigns organization context.
  RLS enforcement happens at the Repo level — each DB operation goes
  through `Repo.with_org_context/2` which sets the role + org variable
  on a checked-out connection for the duration of the call.
  """
  use EstimateWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component

  alias Estimate.{Accounts, Organizations}
  alias Estimate.Accounts.User

  def on_mount(:ensure_org_member, params, _session, socket) do
    org_id = params["org_id"]
    user = socket.assigns.current_user

    if org_id && user do
      # memberships table has no RLS — safe to query without org context
      case Organizations.get_user_membership(user.id, org_id) do
        nil ->
          socket =
            socket
            |> put_flash(:error, "You don't have access to this organization.")
            |> redirect(to: ~p"/organizations")

          {:halt, socket}

        membership ->
          organization = Organizations.get_organization!(org_id)

          # Store org_id and user_id in process dictionary for RLS context.
          # Context functions use Repo.ensure_org_context/1 to
          # automatically wrap DB ops with SET ROLE + set_config.
          Estimate.Repo.put_org_id(org_id)
          Estimate.Repo.put_user_id(user.id)

          touch_activity_async(user, org_id)

          socket =
            socket
            |> assign(:current_organization, organization)
            |> assign(:current_membership, membership)
            |> assign(:org_id, org_id)
            |> maybe_assign_2fa_deadline(membership, user)

          if enforcement_blocks?(membership, user) do
            socket =
              socket
              |> put_flash(:error, "Your organization requires two-factor authentication.")
              |> redirect(to: ~p"/account/two-factor/setup")

            {:halt, socket}
          else
            {:cont, socket}
          end
      end
    else
      socket =
        socket
        |> put_flash(:error, "Organization not found.")
        |> redirect(to: ~p"/organizations")

      {:halt, socket}
    end
  end

  def on_mount(:load_org_if_present, params, _session, socket) do
    org_id = params["org_id"]
    user = socket.assigns.current_user

    if org_id && user do
      case Organizations.get_user_membership(user.id, org_id) do
        nil ->
          {:cont, socket}

        membership ->
          organization = Organizations.get_organization!(org_id)
          Estimate.Repo.put_org_id(org_id)
          Estimate.Repo.put_user_id(user.id)

          socket =
            socket
            |> assign(:current_organization, organization)
            |> assign(:current_membership, membership)
            |> assign(:org_id, org_id)

          {:cont, socket}
      end
    else
      {:cont, socket}
    end
  end

  # Fire-and-forget activity touch. In :test it runs inline so the DB write uses
  # the caller's sandboxed connection (a bare Task.start spawns an unsupervised,
  # unowned process whose query races the SQL sandbox and disconnects on checkin).
  # In prod it runs as a supervised child of Estimate.TaskSupervisor.
  defp touch_activity_async(user, org_id) do
    task_fn = fn -> Accounts.touch_user_activity(user, org_id) end

    if Application.get_env(:estimate, :env) == :test do
      task_fn.()
    else
      Task.Supervisor.start_child(Estimate.TaskSupervisor, task_fn)
    end
  end

  defp enforcement_blocks?(membership, user) do
    membership.totp_required_by != nil and
      not User.totp_enabled?(user) and
      DateTime.compare(DateTime.utc_now(), membership.totp_required_by) == :gt
  end

  defp maybe_assign_2fa_deadline(socket, membership, user) do
    if membership.totp_required_by != nil and not User.totp_enabled?(user) do
      assign(socket, :totp_enforcement_deadline, membership.totp_required_by)
    else
      socket
    end
  end
end
