defmodule Estimate.Repo.Migrations.AddTotpAnd2faEnforcement do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :encrypted_totp_secret, :binary
      add :totp_secret_nonce, :binary
      add :totp_enabled_at, :utc_datetime
      add :totp_backup_codes, :binary
    end

    alter table(:organizations) do
      add :enforce_2fa, :boolean, default: false, null: false
      add :enforce_2fa_grace_period_days, :integer, default: 14, null: false
    end

    alter table(:memberships) do
      add :totp_required_by, :utc_datetime
    end
  end
end
