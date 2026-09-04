defmodule Estimate.Encryption do
  @moduledoc """
  AES-256-GCM with a versioned key ring.

  * v1 — derived from `SECRET_KEY_BASE` (legacy; rotating the Phoenix secret used
    to brick every stored secret).
  * v2 — `ENCRYPTION_KEY` (base64 of 32 random bytes), when configured.

  `encrypt/1` always uses the newest key and returns its version; `decrypt/3`
  uses the version stored beside the ciphertext. Readers re-encrypt lazily
  (see `Estimate.Accounts.Totp` / `Estimate.Organizations`) and
  `mix estimate.rotate_encryption` re-encrypts everything eagerly.
  """

  @aad "estimate-encryption"
  @term {__MODULE__, :ring}

  @spec load_keys() :: :ok
  def load_keys do
    v1 =
      Application.fetch_env!(:estimate, EstimateWeb.Endpoint)
      |> Keyword.fetch!(:secret_key_base)
      |> Plug.Crypto.KeyGenerator.generate("estimate-encryption-v1", length: 32)

    ring =
      case Application.get_env(:estimate, __MODULE__, [])[:key] do
        nil -> %{1 => v1}
        "" -> %{1 => v1}
        b64 -> %{1 => v1, 2 => decode_key!(b64)}
      end

    :persistent_term.put(@term, ring)
    :ok
  end

  def current_version, do: ring() |> Map.keys() |> Enum.max()

  @spec encrypt(binary()) :: {:ok, binary(), binary(), pos_integer()}
  def encrypt(plaintext) when is_binary(plaintext) do
    version = current_version()
    key = Map.fetch!(ring(), version)
    nonce = :crypto.strong_rand_bytes(12)
    {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, @aad, true)
    {:ok, nonce, ct <> tag, version}
  end

  @spec decrypt(binary(), binary(), pos_integer()) ::
          {:ok, binary()} | {:error, :decrypt_failed | :unknown_key_version}
  def decrypt(nonce, ct_with_tag, version)
      when is_binary(nonce) and is_binary(ct_with_tag) and is_integer(version) do
    case Map.fetch(ring(), version) do
      :error ->
        {:error, :unknown_key_version}

      {:ok, key} ->
        size = byte_size(ct_with_tag) - 16
        <<ct::binary-size(size), tag::binary-size(16)>> = ct_with_tag

        case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ct, @aad, tag, false) do
          pt when is_binary(pt) -> {:ok, pt}
          :error -> {:error, :decrypt_failed}
        end
    end
  end

  def decrypt(_, _, _), do: {:error, :decrypt_failed}

  defp ring do
    case :persistent_term.get(@term, nil) do
      nil ->
        load_keys()
        :persistent_term.get(@term)

      ring ->
        ring
    end
  end

  defp decode_key!(b64) do
    case Base.decode64(b64) do
      {:ok, <<key::binary-size(32)>>} -> key
      _ -> raise ArgumentError, "ENCRYPTION_KEY must be base64 of exactly 32 bytes"
    end
  end
end
