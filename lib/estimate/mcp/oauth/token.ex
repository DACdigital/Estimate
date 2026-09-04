defmodule Estimate.MCP.OAuth.Token do
  use Estimate.Schema

  schema "oauth_tokens" do
    field :access_token_hash, :binary, redact: true
    field :refresh_token_hash, :binary, redact: true
    field :family_id, :binary_id
    field :access_expires_at, :utc_datetime
    field :refresh_expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :scope, :string, default: "mcp:read"

    belongs_to :client, Estimate.MCP.OAuth.Client
    belongs_to :code, Estimate.MCP.OAuth.Code
    belongs_to :user, Estimate.Accounts.User
    belongs_to :organization, Estimate.Accounts.Organization

    timestamps(type: :utc_datetime)
  end
end
