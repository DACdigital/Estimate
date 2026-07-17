defmodule Estimate.Repo.Migrations.CreateOauthTables do
  use Ecto.Migration

  def up do
    create table(:oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :redirect_uris, {:array, :string}, null: false
      timestamps(type: :utc_datetime)
    end

    create table(:oauth_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code_hash, :binary, null: false
      add :redirect_uri, :string, null: false
      add :code_challenge, :string, null: false
      add :resource, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      add :client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_codes, [:code_hash])

    create table(:oauth_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :access_token_hash, :binary, null: false
      add :refresh_token_hash, :binary, null: false
      add :family_id, :binary_id, null: false
      add :access_expires_at, :utc_datetime, null: false
      add :refresh_expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :last_used_at, :utc_datetime

      add :client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all),
        null: false

      add :code_id, references(:oauth_codes, type: :binary_id, on_delete: :nilify_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_tokens, [:access_token_hash])
    create unique_index(:oauth_tokens, [:refresh_token_hash])
    create index(:oauth_tokens, [:family_id])
    create index(:oauth_tokens, [:user_id, :organization_id])

    # Auth-infra tables: user-facing ops are own-user scoped; the OAuth flows
    # themselves run via Repo.without_rls (no org context on those requests).
    for table <- ~w(oauth_codes oauth_tokens) do
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

      execute """
      CREATE POLICY own_rows ON #{table} FOR ALL
        USING (organization_id = current_org_id() AND user_id = current_user_id())
        WITH CHECK (organization_id = current_org_id() AND user_id = current_user_id())
      """
    end
  end

  def down do
    for table <- ~w(oauth_tokens oauth_codes) do
      execute "DROP POLICY IF EXISTS own_rows ON #{table}"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
    end

    drop table(:oauth_tokens)
    drop table(:oauth_codes)
    drop table(:oauth_clients)
  end
end
