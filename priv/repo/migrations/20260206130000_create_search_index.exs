defmodule Estimate.Repo.Migrations.CreateSearchIndex do
  use Ecto.Migration

  def up do
    # Enable pg_trgm extension for fuzzy/typo matching
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    create table(:search_index, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :searchable_type, :string, null: false
      add :searchable_id, :binary_id, null: false
      add :title, :string, null: false
      add :subtitle, :string
      add :path_ids, :map, default: %{}
      add :content, :text, null: false
      add :search_vector, :tsvector

      timestamps()
    end

    # Unique constraint on type+id combo
    create unique_index(:search_index, [:searchable_type, :searchable_id])

    # Index for filtering by org and type
    create index(:search_index, [:organization_id, :searchable_type])

    # GIN index for full-text search
    create index(:search_index, [:search_vector], using: :gin)

    # GIN index for trigram fuzzy matching
    execute "CREATE INDEX search_index_trgm_idx ON search_index USING GIN(content gin_trgm_ops)"

    # Trigger to auto-compute search_vector with weighted fields
    execute """
    CREATE OR REPLACE FUNCTION search_index_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.subtitle, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.content, '')), 'C');
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER search_index_vector_update
    BEFORE INSERT OR UPDATE ON search_index
    FOR EACH ROW EXECUTE FUNCTION search_index_trigger()
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS search_index_vector_update ON search_index"
    execute "DROP FUNCTION IF EXISTS search_index_trigger()"

    drop table(:search_index)
  end
end
