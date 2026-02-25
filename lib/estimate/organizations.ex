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

  alias Estimate.Portfolio.{Project, ProjectCollaborator}

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
    do: decrypt_field(org, :openrouter_api_key_nonce, :encrypted_openrouter_api_key)

  def mask_api_key(%Organization{} = org),
    do: org |> get_decrypted_api_key() |> mask_secret()

  ## SMTP Settings

  def update_smtp_settings(%Organization{} = org, attrs) do
    org
    |> Organization.smtp_settings_changeset(attrs)
    |> Repo.update()
  end

  def get_decrypted_smtp_password(%Organization{} = org),
    do: decrypt_field(org, :smtp_password_nonce, :encrypted_smtp_password)

  def mask_smtp_password(%Organization{} = org),
    do: org |> get_decrypted_smtp_password() |> mask_secret()

  defp decrypt_field(org, nonce_field, cipher_field) do
    case {Map.get(org, nonce_field), Map.get(org, cipher_field)} do
      {nil, _} -> nil
      {_, nil} -> nil

      {nonce, ciphertext} ->
        case Estimate.Encryption.decrypt(nonce, ciphertext) do
          {:ok, plaintext} -> plaintext
          _ -> nil
        end
    end
  end

  defp mask_secret(nil), do: nil
  defp mask_secret(s) when byte_size(s) <= 8, do: "****"
  defp mask_secret(s), do: String.slice(s, 0, 4) <> "..." <> String.slice(s, -4, 4)

  def smtp_configured?(%Organization{} = org) do
    org.smtp_host not in [nil, ""] and
      org.smtp_from_email not in [nil, ""] and
      org.encrypted_smtp_password != nil
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
    membership
    |> Membership.changeset(%{role: role})
    |> Repo.update()
  end

  def delete_membership(%Membership{} = membership), do: delete_membership(membership, %{})

  @doc """
  Deletes membership with optional ownership reassignment.
  `reassignments` is a map of `%{project_id => new_owner_user_id}`.
  Validates all project_ids belong to the org and all new owners are org members.
  """
  def delete_membership(%Membership{} = membership, reassignments)
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
          |> Ecto.Multi.delete(:membership, membership)

        case Repo.transaction(multi) do
          {:ok, %{membership: m}} -> {:ok, m}
          {:error, _op, changeset, _} -> {:error, changeset}
        end
      end
    end)
  end

  defp validate_reassignments(reassignments, _org_id, _removed_user_id)
       when map_size(reassignments) == 0,
       do: :ok

  defp validate_reassignments(reassignments, org_id, removed_user_id) do
    project_ids = Map.keys(reassignments)
    new_owner_ids = reassignments |> Map.values() |> Enum.uniq()

    org_project_ids =
      from(p in Project, where: p.id in ^project_ids and p.organization_id == ^org_id, select: p.id)
      |> Repo.all()
      |> MapSet.new()

    member_ids =
      from(m in Membership, where: m.organization_id == ^org_id, select: m.user_id)
      |> Repo.all()
      |> MapSet.new()

    cond do
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

  def accept_invite(%Invite{} = invite, %{id: user_id, email: user_email}) do
    cond do
      not Invite.valid?(invite) ->
        {:error, :expired}

      invite.email != nil and invite.email != user_email ->
        {:error, :email_mismatch}

      true ->
        Ecto.Multi.new()
        |> Ecto.Multi.run(:verify_still_valid, fn _repo, _ ->
          fresh =
            from(i in Invite,
              where:
                i.id == ^invite.id and is_nil(i.accepted_at) and
                  i.expires_at > ^DateTime.utc_now()
            )
            |> Repo.one()

          if fresh, do: {:ok, fresh}, else: {:error, :expired}
        end)
        |> Ecto.Multi.update(:invite, fn %{verify_still_valid: fresh} ->
          Invite.accept_changeset(fresh)
        end)
        |> Ecto.Multi.insert(:membership, fn _ ->
          Membership.changeset(%Membership{}, %{
            user_id: user_id,
            organization_id: invite.organization_id,
            role: invite.role
          })
        end)
        |> Repo.transaction()
        |> case do
          {:ok, result} -> {:ok, result}
          {:error, :verify_still_valid, :expired, _} -> {:error, :expired}
          {:error, _op, changeset, _} -> {:error, changeset}
        end
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

  def approve_join_request(%JoinRequest{} = request, reviewer_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:request, JoinRequest.review_changeset(request, "approved", reviewer_id))
    |> Ecto.Multi.insert(:membership, fn _ ->
      Membership.changeset(%Membership{}, %{
        user_id: request.user_id,
        organization_id: request.organization_id,
        role: "member"
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, _op, changeset, _} -> {:error, changeset}
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
