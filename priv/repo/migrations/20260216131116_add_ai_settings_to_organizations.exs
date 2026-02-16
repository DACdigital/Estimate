defmodule Estimate.Repo.Migrations.AddAiSettingsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :encrypted_openrouter_api_key, :binary
      add :openrouter_api_key_nonce, :binary
      add :openrouter_model, :string, default: "openai/gpt-4o-mini"
      add :openrouter_system_prompt, :text
    end
  end
end
