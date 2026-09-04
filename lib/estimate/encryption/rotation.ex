defmodule Estimate.Encryption.Rotation do
  @moduledoc "Eagerly re-encrypts every stored secret that is not on the current key version."
  import Ecto.Query
  alias Estimate.{Encryption, Repo}
  alias Estimate.Accounts.{Organization, User}

  @spec run() :: %{users: non_neg_integer(), organizations: non_neg_integer()}
  def run do
    current = Encryption.current_version()

    Repo.without_rls(fn ->
      users =
        from(u in User,
          where: not is_nil(u.encrypted_totp_secret) and u.totp_key_version < ^current
        )
        |> Repo.all()
        |> Enum.count(&rotate_user(&1, current))

      orgs =
        from(o in Organization,
          where:
            (not is_nil(o.encrypted_openrouter_api_key) and o.openrouter_key_version < ^current) or
              (not is_nil(o.encrypted_smtp_password) and o.smtp_key_version < ^current)
        )
        |> Repo.all()
        |> Enum.count(&rotate_org(&1, current))

      %{users: users, organizations: orgs}
    end)
  end

  defp rotate_user(user, current) do
    with {:ok, pt} <-
           Encryption.decrypt(
             user.totp_secret_nonce,
             user.encrypted_totp_secret,
             user.totp_key_version
           ),
         {:ok, n, ct, ^current} <- Encryption.encrypt(pt),
         {1, _} <-
           Repo.update_all(from(u in User, where: u.id == ^user.id),
             set: [encrypted_totp_secret: ct, totp_secret_nonce: n, totp_key_version: current]
           ) do
      true
    else
      _ -> false
    end
  end

  defp rotate_org(org, current) do
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

    api or smtp
  end

  defp rotate_field(org, nonce_f, ct_f, ver_f, current) do
    with ct when is_binary(ct) <- Map.get(org, ct_f),
         true <- Map.get(org, ver_f) < current,
         {:ok, pt} <- Encryption.decrypt(Map.get(org, nonce_f), ct, Map.get(org, ver_f)),
         {:ok, n, new_ct, ^current} <- Encryption.encrypt(pt),
         {1, _} <-
           Repo.update_all(from(o in Organization, where: o.id == ^org.id),
             set: [{ct_f, new_ct}, {nonce_f, n}, {ver_f, current}]
           ) do
      true
    else
      _ -> false
    end
  end
end
