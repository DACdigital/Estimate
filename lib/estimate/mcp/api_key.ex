defmodule Estimate.MCP.APIKey do
  use Estimate.Schema

  import Ecto.Changeset

  schema "mcp_api_keys" do
    field :key_hash, :binary, redact: true
    field :key_prefix, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, Estimate.Accounts.User
    belongs_to :organization, Estimate.Accounts.Organization

    timestamps()
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:key_hash, :key_prefix, :user_id, :organization_id])
    |> validate_required([:key_hash, :key_prefix, :user_id, :organization_id])
    |> unique_constraint([:user_id, :organization_id])
    |> unique_constraint(:key_hash)
  end
end
