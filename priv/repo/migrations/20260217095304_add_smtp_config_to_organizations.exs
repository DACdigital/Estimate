defmodule Estimate.Repo.Migrations.AddSmtpConfigToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :smtp_host, :string
      add :smtp_port, :integer
      add :smtp_username, :string
      add :encrypted_smtp_password, :binary
      add :smtp_password_nonce, :binary
      add :smtp_from_name, :string
      add :smtp_from_email, :string
    end
  end
end
