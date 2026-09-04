defmodule Estimate.MCP.OAuth.Code do
  use Estimate.Schema

  schema "oauth_codes" do
    field :code_hash, :binary, redact: true
    field :redirect_uri, :string
    field :code_challenge, :string
    field :resource, :string
    field :scope, :string, default: "mcp:read"
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :client, Estimate.MCP.OAuth.Client
    belongs_to :user, Estimate.Accounts.User
    belongs_to :organization, Estimate.Accounts.Organization

    timestamps(type: :utc_datetime)
  end
end
