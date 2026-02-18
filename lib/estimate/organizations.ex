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

  def get_decrypted_api_key(%Organization{} = org) do
    case {org.openrouter_api_key_nonce, org.encrypted_openrouter_api_key} do
      {nil, _} -> nil
      {_, nil} -> nil

      {nonce, ciphertext} ->
        case Estimate.Encryption.decrypt(nonce, ciphertext) do
          {:ok, plaintext} -> plaintext
          _ -> nil
        end
    end
  end

  def mask_api_key(%Organization{} = org) do
    case get_decrypted_api_key(org) do
      nil -> nil
      key when byte_size(key) <= 8 -> "****"
      key -> String.slice(key, 0, 4) <> "..." <> String.slice(key, -4, 4)
    end
  end

  ## SMTP Settings

  def update_smtp_settings(%Organization{} = org, attrs) do
    org
    |> Organization.smtp_settings_changeset(attrs)
    |> Repo.update()
  end

  def get_decrypted_smtp_password(%Organization{} = org) do
    case {org.smtp_password_nonce, org.encrypted_smtp_password} do
      {nil, _} -> nil
      {_, nil} -> nil

      {nonce, ciphertext} ->
        case Estimate.Encryption.decrypt(nonce, ciphertext) do
          {:ok, plaintext} -> plaintext
          _ -> nil
        end
    end
  end

  def mask_smtp_password(%Organization{} = org) do
    case get_decrypted_smtp_password(org) do
      nil -> nil
      pw when byte_size(pw) <= 8 -> "****"
      pw -> String.slice(pw, 0, 4) <> "..." <> String.slice(pw, -4, 4)
    end
  end

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

  def delete_membership(%Membership{} = membership) do
    Repo.delete(membership)
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

  def accept_invite(%Invite{} = invite, user_id) do
    unless Invite.valid?(invite) do
      {:error, :expired}
    else
      Ecto.Multi.new()
      |> Ecto.Multi.run(:verify_still_valid, fn _repo, _ ->
        # Re-check at DB level to prevent race condition
        fresh =
          from(i in Invite,
            where:
              i.id == ^invite.id and is_nil(i.accepted_at) and i.expires_at > ^DateTime.utc_now()
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
end
