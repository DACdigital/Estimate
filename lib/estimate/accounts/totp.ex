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
    {:ok, nonce, ciphertext} = Encryption.encrypt(secret)
    {nonce, ciphertext}
  end

  def decrypt_secret(nonce, ciphertext) do
    Encryption.decrypt(nonce, ciphertext)
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
    {nonce, ciphertext} = encrypt_secret(secret)
    encoded_hashes = Jason.encode!(backup_hashes)

    user
    |> change(%{
      encrypted_totp_secret: ciphertext,
      totp_secret_nonce: nonce,
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
      totp_enabled_at: nil,
      totp_backup_codes: nil
    })
    |> Repo.update()
  end

  def get_decrypted_secret(%User{totp_secret_nonce: nonce, encrypted_totp_secret: ct})
      when is_binary(nonce) and is_binary(ct) do
    decrypt_secret(nonce, ct)
  end

  def get_decrypted_secret(_), do: {:error, :no_secret}

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

  def valid_code_or_backup?(%User{} = user, secret, code) do
    valid_code?(secret, code) or match?({:ok, _}, consume_backup_code(user, code))
  end

  defp hash_code(code) do
    :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
  end
end
