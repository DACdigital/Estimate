defmodule Estimate.Repo.Migrations.AddEncryptionKeyVersions do
  use Ecto.Migration

  # All existing ciphertexts were produced with key v1 (derived from SECRET_KEY_BASE).
  def change do
    alter table(:users) do
      add :totp_key_version, :integer, null: false, default: 1
    end

    alter table(:organizations) do
      add :openrouter_key_version, :integer, null: false, default: 1
      add :smtp_key_version, :integer, null: false, default: 1
    end
  end
end
