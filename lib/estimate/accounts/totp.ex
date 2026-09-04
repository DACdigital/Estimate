defmodule Estimate.Accounts.Totp do
  @moduledoc "TOTP two-factor authentication helpers."

  import Ecto.Changeset
  alias Estimate.Accounts.User
  alias Estimate.{Encryption, Repo}

  @issuer "EstiMate"
  @backup_code_count 10
  @backup_code_length 8

  def generate_secret, do: NimbleTOTP.secret()

  def generate_otpauth_uri(email, secret) do
    NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)
  end

  def generate_qr_svg(otpauth_uri) do
    otpauth_uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 264)
  end

  def valid_code?(secret, code) do
    NimbleTOTP.valid?(secret, code)
  end

  def encrypt_secret(secret) do
    {:ok, nonce, ciphertext, version} = Encryption.encrypt(secret)
    {nonce, ciphertext, version}
  end

  def generate_backup_codes do
    plain_codes =
      for _ <- 1..@backup_code_count do
        :crypto.strong_rand_bytes(@backup_code_length)
        |> Base.encode32(padding: false)
        |> binary_part(0, @backup_code_length)
        |> String.downcase()
      end

    hashed_codes = Enum.map(plain_codes, &hash_code/1)
    {plain_codes, hashed_codes}
  end

  def verify_backup_code(code, hashed_codes) when is_list(hashed_codes) do
    hashed_input = hash_code(String.downcase(String.trim(code)))

    case Enum.find_index(hashed_codes, &Plug.Crypto.secure_compare(&1, hashed_input)) do
      nil -> :error
      idx -> {:ok, List.delete_at(hashed_codes, idx)}
    end
  end

  def enable_totp(%User{} = user, secret, backup_hashes) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {nonce, ciphertext, version} = encrypt_secret(secret)
    encoded_hashes = Jason.encode!(backup_hashes)

    user
    |> change(%{
      encrypted_totp_secret: ciphertext,
      totp_secret_nonce: nonce,
      totp_key_version: version,
      totp_enabled_at: now,
      totp_backup_codes: encoded_hashes
    })
    |> Repo.update()
  end

  def disable_totp(%User{} = user) do
    user
    |> change(%{
      encrypted_totp_secret: nil,
      totp_secret_nonce: nil,
      totp_key_version: 1,
      totp_enabled_at: nil,
      totp_backup_codes: nil
    })
    |> Repo.update()
  end

  def get_decrypted_secret(
        %User{totp_secret_nonce: nonce, encrypted_totp_secret: ct, totp_key_version: version} =
          user
      )
      when is_binary(nonce) and is_binary(ct) do
    with {:ok, secret} <- Encryption.decrypt(nonce, ct, version) do
      maybe_reencrypt_secret(user, secret, version)
      {:ok, secret}
    end
  end

  def get_decrypted_secret(_), do: {:error, :no_secret}

  defp maybe_reencrypt_secret(user, secret, version) do
    if version < Encryption.current_version() do
      {nonce, ciphertext, new_version} = encrypt_secret(secret)

      user
      |> change(%{
        encrypted_totp_secret: ciphertext,
        totp_secret_nonce: nonce,
        totp_key_version: new_version
      })
      |> Repo.update()
    end

    :ok
  end

  def get_backup_hashes(%User{totp_backup_codes: codes}) when is_binary(codes) do
    Jason.decode!(codes)
  end

  def get_backup_hashes(_), do: []

  def consume_backup_code(%User{} = user, code) do
    hashes = get_backup_hashes(user)

    case verify_backup_code(code, hashes) do
      {:ok, remaining} ->
        user
        |> change(%{totp_backup_codes: Jason.encode!(remaining)})
        |> Repo.update()

      :error ->
        :error
    end
  end

  @doc """
  Verifies a TOTP code for an enrolled user. A code is accepted only if it is
  newer than the last accepted one (`since:`), so a captured code cannot be
  replayed on any node; the acceptance timestamp is persisted.
  """
  def verify_code(%User{} = user, secret, code) do
    if NimbleTOTP.valid?(secret, code, since: user.totp_last_used_at) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      user |> change(%{totp_last_used_at: now}) |> Repo.update()
    else
      :error
    end
  end

  def verify_code_or_backup(%User{} = user, secret, code) do
    case verify_code(user, secret, code) do
      {:ok, user} -> {:ok, user}
      :error -> consume_backup_code(user, code)
    end
  end

  defp hash_code(code) do
    :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
  end
end
