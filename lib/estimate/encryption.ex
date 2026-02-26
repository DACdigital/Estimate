defmodule Estimate.Encryption do
  @aad "estimate-encryption"

  def encrypt(plaintext) when is_binary(plaintext) do
    key = derive_key()
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, @aad, true)

    {:ok, nonce, ciphertext <> tag}
  end

  def decrypt(nonce, ciphertext_with_tag)
      when is_binary(nonce) and is_binary(ciphertext_with_tag) do
    key = derive_key()
    tag_size = 16
    ct_size = byte_size(ciphertext_with_tag) - tag_size
    <<ciphertext::binary-size(ct_size), tag::binary-size(tag_size)>> = ciphertext_with_tag

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :decrypt_failed}
    end
  end

  def decrypt(_, _), do: {:error, :decrypt_failed}

  defp derive_key do
    secret = EstimateWeb.Endpoint.config(:secret_key_base)
    :crypto.hash(:sha256, secret)
  end
end
