defmodule Estimate.Organizations do
  @moduledoc """
  Context for organizations, memberships, invites, and join requests.
  """

  import Ecto.Query
  alias Estimate.Repo

  alias Estimate.Accounts.{
    Organization,
    Membership,
    Invite,
    JoinRequest
  }

  alias Estimate.MCP.APIKey
  alias Estimate.Portfolio.{Project, ProjectCollaborator}

  @dialyzer :no_opaque

  ## Organization

  def get_organization!(id), do: Repo.get!(Organization, id)

  def list_user_organizations(user_id) do
    from(o in Organization,
      join: m in Membership,
      on: m.organization_id == o.id,
      where: m.user_id == ^user_id,
      select: {o, m.role}
    )
    |> Repo.all()
  end

  def get_user_membership(user_id, org_id) do
    Repo.get_by(Membership, user_id: user_id, organization_id: org_id)
  end

  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  def update_organization(%Organization{} = org, attrs) do
    org
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  def change_organization(%Organization{} = org, attrs \\ %{}) do
    Organization.changeset(org, attrs)
  end

  ## AI Settings

  def update_ai_settings(%Organization{} = org, attrs) do
    org
    |> Organization.ai_settings_changeset(attrs)
    |> Repo.update()
  end

  def get_decrypted_api_key(%Organization{} = org),
    do:
      decrypt_field(
        org,
        :openrouter_api_key_nonce,
        :encrypted_openrouter_api_key,
        :openrouter_key_version
      )

  def mask_api_key(%Organization{} = org),
    do: org |> get_decrypted_api_key() |> mask_secret()

  ## MCP Settings

  def update_mcp_settings(%Organization{} = org, attrs) do
    org
    |> Organization.mcp_settings_changeset(attrs)
    |> Repo.update()
  end

  def update_mcp_write_settings(%Organization{} = org, attrs) do
    org
    |> Organization.mcp_write_settings_changeset(attrs)
    |> Repo.update()
  end

  def mcp_write_enabled?(org_id) when is_binary(org_id) do
    Repo.ensure_org_context(fn ->
      from(o in Organization, where: o.id == ^org_id, select: o.mcp_write_enabled)
      |> Repo.one()
    end) == true
  end

  ## SMTP Settings

  def update_smtp_settings(%Organization{} = org, attrs) do
    org
    |> Organization.smtp_settings_changeset(attrs)
    |> Repo.update()
  end

  def get_decrypted_smtp_password(%Organization{} = org),
    do: decrypt_field(org, :smtp_password_nonce, :encrypted_smtp_password, :smtp_key_version)

  def mask_smtp_password(%Organization{} = org),
    do: org |> get_decrypted_smtp_password() |> mask_secret()

  defp decrypt_field(org, nonce_field, cipher_field, version_field) do
    case {Map.get(org, nonce_field), Map.get(org, cipher_field), Map.get(org, version_field)} do
      {nil, _, _} ->
        nil

      {_, nil, _} ->
        nil

      {nonce, ciphertext, version} ->
        case Estimate.Encryption.decrypt(nonce, ciphertext, version) do
          {:ok, plaintext} ->
            maybe_reencrypt_field(
              org,
              plaintext,
              version,
              nonce_field,
              cipher_field,
              version_field
            )

            plaintext

          _ ->
            nil
        end
    end
  end

  defp maybe_reencrypt_field(org, plaintext, version, nonce_field, cipher_field, version_field) do
    if version < Estimate.Encryption.current_version() do
      {:ok, nonce, ciphertext, new_version} = Estimate.Encryption.encrypt(plaintext)

      from(o in Organization, where: o.id == ^org.id)
      |> Repo.update_all(
        set: [
          {nonce_field, nonce},
          {cipher_field, ciphertext},
          {version_field, new_version}
        ]
      )
    end

    :ok
  end

  defp mask_secret(nil), do: nil
  defp mask_secret(s) when byte_size(s) <= 8, do: "****"
  defp mask_secret(s), do: String.slice(s, 0, 4) <> "..." <> String.slice(s, -4, 4)

  def smtp_configured?(%Organization{} = org) do
    org.smtp_host not in [nil, ""] and
      org.smtp_from_email not in [nil, ""] and
      org.encrypted_smtp_password != nil
  end

  ## Security Settings (2FA enforcement)

  def update_security_settings(%Organization{} = org, attrs) do
    changeset = Organization.security_settings_changeset(org, attrs)

    case Repo.update(changeset) do
      {:ok, updated_org} ->
        handle_2fa_enforcement_change(updated_org, org.enforce_2fa)
        {:ok, updated_org}

      error ->
        error
    end
  end

  defp handle_2fa_enforcement_change(%Organization{enforce_2fa: true} = org, false) do
    # Toggled ON: set deadline on members without TOTP
    Repo.ensure_org_context(fn ->
      deadline =
        DateTime.utc_now()
        |> DateTime.add(org.enforce_2fa_grace_period_days * 86400, :second)
        |> DateTime.truncate(:second)

      from(m in Membership,
        where: m.organization_id == ^org.id,
        join: u in assoc(m, :user),
        where: is_nil(u.totp_enabled_at) and is_nil(m.totp_required_by)
      )
      |> Repo.update_all(set: [totp_required_by: deadline])
    end)
  end

  defp handle_2fa_enforcement_change(%Organization{enforce_2fa: false} = org, true) do
    # Toggled OFF: clear all deadlines
    Repo.ensure_org_context(fn ->
      from(m in Membership, where: m.organization_id == ^org.id)
      |> Repo.update_all(set: [totp_required_by: nil])
    end)
  end

  defp handle_2fa_enforcement_change(_org, _prev), do: :ok

  @doc "Set totp_required_by on a membership joining an enforcing org."
  def set_2fa_deadline_if_needed(%Membership{} = membership, %Organization{} = org) do
    if org.enforce_2fa do
      deadline =
        DateTime.utc_now()
        |> DateTime.add(org.enforce_2fa_grace_period_days * 86400, :second)
        |> DateTime.truncate(:second)

      membership
      |> Ecto.Changeset.change(totp_required_by: deadline)
      |> Repo.update()
    else
      {:ok, membership}
    end
  end

  @doc "Clear totp_required_by on all memberships for a user who enabled TOTP."
  def clear_2fa_deadlines_for_user(user_id) do
    from(m in Membership, where: m.user_id == ^user_id and not is_nil(m.totp_required_by))
    |> Repo.update_all(set: [totp_required_by: nil])
  end

  def count_members_without_2fa(org_id) do
    Repo.ensure_org_context(fn ->
      from(m in Membership,
        join: u in assoc(m, :user),
        where: m.organization_id == ^org_id and is_nil(u.totp_enabled_at)
      )
      |> Repo.aggregate(:count)
    end)
  end

  ## Membership

  def create_membership(attrs) do
    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert()
  end

  def list_organization_members(org_id) do
    from(m in Membership,
      where: m.organization_id == ^org_id,
      preload: [:user]
    )
    |> Repo.all()
  end

  def update_membership_role(%Membership{} = membership, role) do
    if role in Membership.assignable_roles() do
      membership |> Membership.changeset(%{role: role}) |> Repo.update()
    else
      {:error, :invalid_role}
    end
  end

  @doc """
  Whether `actor_user_id` may change/remove the given membership:
  not an owner, and not the actor themselves. False for a nil/non-membership.
  """
  def manageable_member?(%Membership{} = membership, actor_user_id),
    do: membership.role != "owner" and membership.user_id != actor_user_id

  def manageable_member?(_membership, _actor_user_id), do: false

  @doc """
  Owner-only: makes `target_user_id` the owner and demotes the actor to admin, atomically.

  Both writes are row-counted inside one transaction (re-checking role/org in the WHERE
  clause) so a concurrent change to either membership (e.g. the target being removed from
  the org between the pre-check and the write) rolls the whole transfer back instead of
  silently leaving the org with zero owners. That race surfaces as `{:error, :not_a_member}`.
  """
  def transfer_ownership(org_id, actor_user_id, target_user_id) do
    cond do
      actor_user_id == target_user_id ->
        {:error, :same_user}

      true ->
        actor = get_user_membership(actor_user_id, org_id)
        target = get_user_membership(target_user_id, org_id)

        cond do
          is_nil(actor) or actor.role != "owner" -> {:error, :not_owner}
          is_nil(target) -> {:error, :not_a_member}
          true -> do_transfer(org_id, actor, target)
        end
    end
  end

  defp do_transfer(org_id, actor, target) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :new_owner,
      from(m in Membership, where: m.id == ^target.id and m.organization_id == ^org_id),
      set: [role: "owner", updated_at: now]
    )
    |> Ecto.Multi.update_all(
      :previous_owner,
      from(m in Membership,
        where: m.id == ^actor.id and m.organization_id == ^org_id and m.role == "owner"
      ),
      set: [role: "admin", updated_at: now]
    )
    |> Ecto.Multi.run(:verify, fn _repo, changes -> verify_transfer_counts(changes) end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        {:ok,
         %{
           new_owner: get_user_membership(target.user_id, org_id),
           previous_owner: get_user_membership(actor.user_id, org_id)
         }}

      {:error, :verify, :stale, _} ->
        {:error, :not_a_member}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc false
  def verify_transfer_counts(%{new_owner: {n1, _}, previous_owner: {n2, _}}) do
    if n1 == 1 and n2 == 1, do: {:ok, :ok}, else: {:error, :stale}
  end

  @doc "Self-service leave. Refused for the org's only owner and for sole owners of any project."
  def leave_organization(user_id, org_id) do
    case get_user_membership(user_id, org_id) do
      nil ->
        {:error, :not_a_member}

      membership ->
        cond do
          membership.role == "owner" and count_owners(org_id) == 1 ->
            {:error, :sole_owner}

          Estimate.Portfolio.list_sole_owned_projects(user_id, org_id) != [] ->
            {:error, :sole_project_owner}

          true ->
            delete_membership(membership, %{})
        end
    end
  end

  defp count_owners(org_id) do
    from(m in Membership, where: m.organization_id == ^org_id and m.role == "owner")
    |> Repo.aggregate(:count)
  end

  @doc """
  Deletes membership with optional ownership reassignment.
  `reassignments` is a map of `%{project_id => new_owner_user_id}`.
  Validates all project_ids belong to the org and all new owners are org members.
  """
  def delete_membership(%Membership{} = membership, reassignments \\ %{})
      when is_map(reassignments) do
    Repo.ensure_org_context(fn ->
      org_id = membership.organization_id
      removed_user_id = membership.user_id

      with :ok <- validate_reassignments(reassignments, org_id, removed_user_id) do
        org_project_ids =
          from(p in Project, where: p.organization_id == ^org_id, select: p.id)

        multi =
          reassignments
          |> Enum.reduce(Ecto.Multi.new(), fn {project_id, new_owner_id}, multi ->
            Ecto.Multi.run(multi, {:reassign, project_id}, fn _repo, _ ->
              upsert_owner(project_id, new_owner_id)
            end)
          end)
          |> Ecto.Multi.delete_all(
            :collaborators,
            from(pc in ProjectCollaborator,
              where: pc.user_id == ^removed_user_id and pc.project_id in subquery(org_project_ids)
            )
          )
          |> Ecto.Multi.run(:revoke_mcp_key, fn _repo, _changes ->
            # Otherwise a rejoin silently resurrects the old key (verify_api_key
            # rejects while removed, but the row outlives the membership).
            # An admin deleting ANOTHER user's key row hits the mcp_api_keys
            # own-key RLS policy (user_id = current_user_id()), which would
            # silently filter this out under the acting admin's org context —
            # bypass via without_rls, same system-level escape hatch as
            # MCP.verify_api_key/1. Delete directly rather than through
            # MCP.revoke_api_key/2: that function wraps itself in
            # ensure_org_context, which would re-set the blocking role/context
            # right back inside this without_rls block.
            Repo.without_rls(fn ->
              Repo.delete_all(
                from(k in APIKey,
                  where: k.user_id == ^removed_user_id and k.organization_id == ^org_id
                )
              )

              Estimate.MCP.OAuth.revoke_for_membership(removed_user_id, org_id)
            end)

            {:ok, :revoked}
          end)
          |> Ecto.Multi.delete(:membership, membership)

        case Repo.transaction(multi) do
          {:ok, %{membership: m}} -> {:ok, m}
          {:error, _op, changeset, _} -> {:error, changeset}
        end
      end
    end)
  end

  defp validate_reassignments(reassignments, org_id, removed_user_id) do
    sole_owned_ids =
      Estimate.Portfolio.list_sole_owned_projects(removed_user_id, org_id)
      |> Enum.map(fn {p, _count} -> p.id end)
      |> MapSet.new()

    mapped_ids = reassignments |> Map.keys() |> MapSet.new()
    project_ids = Map.keys(reassignments)
    new_owner_ids = reassignments |> Map.values() |> Enum.uniq()

    org_project_ids =
      from(p in Project,
        where: p.id in ^project_ids and p.organization_id == ^org_id,
        select: p.id
      )
      |> Repo.all()
      |> MapSet.new()

    member_ids =
      from(m in Membership, where: m.organization_id == ^org_id, select: m.user_id)
      |> Repo.all()
      |> MapSet.new()

    cond do
      not MapSet.subset?(sole_owned_ids, mapped_ids) ->
        {:error, :incomplete_reassignment}

      Enum.any?(project_ids, &(not MapSet.member?(org_project_ids, &1))) ->
        {:error, :invalid_project}

      Enum.any?(new_owner_ids, &(&1 == removed_user_id)) ->
        {:error, :self_reassignment}

      Enum.any?(new_owner_ids, &(not MapSet.member?(member_ids, &1))) ->
        {:error, :invalid_member}

      true ->
        :ok
    end
  end

  defp upsert_owner(project_id, user_id) do
    case Repo.get_by(ProjectCollaborator, project_id: project_id, user_id: user_id) do
      nil ->
        %ProjectCollaborator{}
        |> ProjectCollaborator.changeset(%{
          project_id: project_id,
          user_id: user_id,
          role: "owner"
        })
        |> Repo.insert()

      existing ->
        existing
        |> ProjectCollaborator.changeset(%{role: "owner"})
        |> Repo.update()
    end
  end

  ## Invites

  def create_invite(org_id, attrs, invited_by_id) do
    %Invite{}
    |> Invite.changeset(
      Map.merge(attrs, %{organization_id: org_id, invited_by_id: invited_by_id})
    )
    |> Repo.insert()
  end

  def get_valid_invite_by_token(token) do
    invite =
      from(i in Invite,
        where: i.token == ^token,
        preload: [:organization]
      )
      |> Repo.one()

    if invite && Invite.valid?(invite), do: invite
  end

  @doc "Composable Ecto.Multi steps for accepting an invite; user resolved via `user_getter`."
  def invite_acceptance_multi(%Invite{} = invite, user_getter) when is_function(user_getter, 1) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:check_invite, fn _repo, changes ->
      user = user_getter.(changes)

      cond do
        not Invite.valid?(invite) -> {:error, :expired}
        invite.email != nil and invite.email != user.email -> {:error, :email_mismatch}
        get_user_membership(user.id, invite.organization_id) -> {:error, :already_member}
        true -> {:ok, user}
      end
    end)
    |> Ecto.Multi.run(:claim, fn repo, _ ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      case repo.update_all(
             from(i in Invite,
               where: i.id == ^invite.id and is_nil(i.accepted_at) and i.expires_at > ^now
             ),
             set: [accepted_at: now]
           ) do
        {1, _} -> {:ok, :claimed}
        _ -> {:error, :expired}
      end
    end)
    |> Ecto.Multi.insert(:membership, fn %{check_invite: user} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        organization_id: invite.organization_id,
        role: invite.role
      })
    end)
    |> Ecto.Multi.update_all(
      :resolve_join_requests,
      fn %{check_invite: user} ->
        from(jr in JoinRequest,
          where:
            jr.user_id == ^user.id and jr.organization_id == ^invite.organization_id and
              jr.status == "pending"
        )
      end,
      # An admin's invite is a pre-approval: resolve any pending join request
      # so it can't linger and make approve_join_request collide with the
      # membership created here.
      set: [
        status: "approved",
        reviewed_by_id: invite.invited_by_id,
        reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end

  def accept_invite(%Invite{} = invite, %{id: _, email: _} = user) do
    invite
    |> invite_acceptance_multi(fn _ -> user end)
    |> Repo.transaction()
    |> case do
      {:ok, result} ->
        org = get_organization!(invite.organization_id)
        set_2fa_deadline_if_needed(result.membership, org)
        {:ok, result}

      {:error, :check_invite, reason, _} ->
        {:error, reason}

      {:error, :claim, :expired, _} ->
        {:error, :expired}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  def list_organization_invites(org_id) do
    from(i in Invite,
      where: i.organization_id == ^org_id and is_nil(i.accepted_at),
      preload: [:invited_by]
    )
    |> Repo.all()
  end

  def create_invite_code(org_id, role, invited_by_id) do
    %Invite{}
    |> Invite.code_changeset(%{
      organization_id: org_id,
      role: role,
      invited_by_id: invited_by_id
    })
    |> Repo.insert()
  end

  def get_valid_invite_by_code(code) when is_binary(code) do
    code = String.upcase(String.trim(code))

    invite =
      from(i in Invite,
        where: i.code == ^code,
        preload: [:organization]
      )
      |> Repo.one()

    if invite && Invite.valid?(invite), do: invite
  end

  def get_valid_invite_by_code(_), do: nil

  def delete_invite(%Invite{} = invite) do
    Repo.delete(invite)
  end

  ## Join Requests

  def create_join_request(user_id, org_id) do
    %JoinRequest{}
    |> JoinRequest.changeset(%{user_id: user_id, organization_id: org_id})
    |> Repo.insert()
  end

  @doc "Builds an unsaved JoinRequest changeset (for composing into a Multi)."
  def build_join_request(user_id, org_id) do
    JoinRequest.changeset(%JoinRequest{}, %{user_id: user_id, organization_id: org_id})
  end

  def approve_join_request(%JoinRequest{} = request, reviewer_id) do
    if request.status != "pending" do
      {:error, :not_pending}
    else
      do_approve_join_request(request, reviewer_id)
    end
  end

  defp do_approve_join_request(%JoinRequest{} = request, reviewer_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:request, JoinRequest.review_changeset(request, "approved", reviewer_id))
    |> Ecto.Multi.run(:existing_membership, fn _repo, _ ->
      # The requester may have become a member since requesting (e.g. redeemed
      # an invite code) — approving must resolve the request, not fail on the
      # memberships unique index.
      {:ok, get_user_membership(request.user_id, request.organization_id)}
    end)
    |> Ecto.Multi.run(:membership, fn _repo, %{existing_membership: existing} ->
      case existing do
        nil ->
          create_membership(%{
            user_id: request.user_id,
            organization_id: request.organization_id,
            role: "member"
          })

        %Membership{} = membership ->
          {:ok, membership}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{existing_membership: nil} = result} ->
        org = get_organization!(request.organization_id)
        set_2fa_deadline_if_needed(result.membership, org)
        {:ok, result}

      {:ok, result} ->
        {:ok, result}

      {:error, _op, changeset, _} ->
        {:error, changeset}
    end
  end

  def reject_join_request(%JoinRequest{} = request, reviewer_id) do
    request
    |> JoinRequest.review_changeset("rejected", reviewer_id)
    |> Repo.update()
  end

  def list_pending_join_requests(org_id) do
    from(jr in JoinRequest,
      where: jr.organization_id == ^org_id and jr.status == "pending",
      preload: [:user]
    )
    |> Repo.all()
  end

  def get_join_request!(id), do: Repo.get!(JoinRequest, id)

  def get_join_request!(id, org_id) do
    from(jr in JoinRequest, where: jr.id == ^id and jr.organization_id == ^org_id)
    |> Repo.one!()
  end
end
