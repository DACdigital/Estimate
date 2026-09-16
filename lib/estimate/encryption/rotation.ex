defmodule Estimate.Encryption.Rotation do
  @moduledoc "Eagerly re-encrypts every stored secret that is not on the current key version."
  import Ecto.Query
  require Logger
  alias Estimate.{Encryption, Repo}
  alias Estimate.Accounts.{Organization, User}

  @spec run() :: %{
          users: non_neg_integer(),
          users_failed: non_neg_integer(),
          organizations: non_neg_integer(),
          organizations_failed: non_neg_integer()
        }
  def run do
    current = Encryption.current_version()

    # users/organizations have no RLS policies (see the RLS migrations), so
    # this needs no Repo.without_rls escape hatch.
    {users, users_failed} =
      from(u in User,
        where: not is_nil(u.encrypted_totp_secret) and u.totp_key_version < ^current
      )
      |> Repo.all()
      |> Enum.reduce({0, 0}, fn user, {ok, failed} ->
        case rotate_user(user, current) do
          :ok -> {ok + 1, failed}
          :failed -> {ok, failed + 1}
          :unchanged -> {ok, failed}
        end
      end)

    {orgs, orgs_failed} =
      from(o in Organization,
        where:
          (not is_nil(o.encrypted_openrouter_api_key) and o.openrouter_key_version < ^current) or
            (not is_nil(o.encrypted_smtp_password) and o.smtp_key_version < ^current)
      )
      |> Repo.all()
      |> Enum.reduce({0, 0}, fn org, {ok, failed} ->
        case rotate_org(org, current) do
          :ok -> {ok + 1, failed}
          :failed -> {ok, failed + 1}
          :unchanged -> {ok, failed}
        end
      end)

    %{
      users: users,
      users_failed: users_failed,
      organizations: orgs,
      organizations_failed: orgs_failed
    }
  end

  # Public for tests only. Returns :ok (rotated), :unchanged (the row was
  # already moved off `user.totp_key_version` by the lazy read-path between
  # our SELECT and this UPDATE — the WHERE on the version we read makes that
  # a 0-row update instead of an overwrite), or :failed (logged).
  @doc false
  def rotate_user(user, current) do
    old_version = user.totp_key_version

    with {:ok, pt} <-
           Encryption.decrypt(user.totp_secret_nonce, user.encrypted_totp_secret, old_version),
         {:ok, n, ct, ^current} <- Encryption.encrypt(pt),
         {rows, _} when rows in [0, 1] <-
           Repo.update_all(
             from(u in User, where: u.id == ^user.id and u.totp_key_version == ^old_version),
             set: [encrypted_totp_secret: ct, totp_secret_nonce: n, totp_key_version: current]
           ) do
      if rows == 1, do: :ok, else: :unchanged
    else
      reason ->
        Logger.error("rotate: could not re-encrypt users #{user.id}: #{inspect(reason)}")
        :failed
    end
  end

  @doc false
  def rotate_org(org, current) do
    api =
      rotate_field(
        org,
        :openrouter_api_key_nonce,
        :encrypted_openrouter_api_key,
        :openrouter_key_version,
        current
      )

    smtp =
      rotate_field(
        org,
        :smtp_password_nonce,
        :encrypted_smtp_password,
        :smtp_key_version,
        current
      )

    cond do
      :failed in [api, smtp] -> :failed
      :ok in [api, smtp] -> :ok
      true -> :unchanged
    end
  end

  # Returns :ok (rotated), :unchanged (nothing stored on that field, already
  # on the current version, or the row was moved off the version we read by
  # the lazy read-path — the WHERE on `ver_f` turns that race into a 0-row
  # update), or :failed (logged, reason from the `with` else).
  defp rotate_field(org, nonce_f, ct_f, ver_f, current) do
    old_version = Map.get(org, ver_f)

    with ct when is_binary(ct) <- Map.get(org, ct_f),
         true <- old_version < current,
         {:ok, pt} <- Encryption.decrypt(Map.get(org, nonce_f), ct, old_version),
         {:ok, n, new_ct, ^current} <- Encryption.encrypt(pt),
         {rows, _} when rows in [0, 1] <-
           Repo.update_all(
             from(o in Organization,
               where: o.id == ^org.id and field(o, ^ver_f) == ^old_version
             ),
             set: [{ct_f, new_ct}, {nonce_f, n}, {ver_f, current}]
           ) do
      if rows == 1, do: :ok, else: :unchanged
    else
      nil ->
        :unchanged

      false ->
        :unchanged

      reason ->
        Logger.error("rotate: could not re-encrypt organizations #{org.id}: #{inspect(reason)}")
        :failed
    end
  end
end
