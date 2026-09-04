defmodule Estimate.Accounts.Organization do
  use Estimate.Schema
  import Ecto.Changeset

  alias Estimate.Encryption

  schema "organizations" do
    field :name, :string
    field :encrypted_openrouter_api_key, :binary, redact: true
    field :openrouter_api_key_nonce, :binary, redact: true
    field :openrouter_key_version, :integer, default: 1
    field :openrouter_model, :string
    field :openrouter_system_prompt, :string

    field :smtp_host, :string
    field :smtp_port, :integer
    field :smtp_username, :string
    field :encrypted_smtp_password, :binary, redact: true
    field :smtp_password_nonce, :binary, redact: true
    field :smtp_key_version, :integer, default: 1
    field :smtp_from_name, :string
    field :smtp_from_email, :string

    field :rates_fetched_at, :utc_datetime

    # 2FA enforcement
    field :enforce_2fa, :boolean, default: false
    field :enforce_2fa_grace_period_days, :integer, default: 14

    field :mcp_enabled, :boolean, default: false
    field :mcp_write_enabled, :boolean, default: false

    # Virtual — for form input only, never persisted
    field :openrouter_api_key, :string, virtual: true, redact: true
    field :smtp_password, :string, virtual: true, redact: true

    has_many :memberships, Estimate.Accounts.Membership
    has_many :users, through: [:memberships, :user]
    has_many :invites, Estimate.Accounts.Invite
    has_many :join_requests, Estimate.Accounts.JoinRequest
    has_many :customers, Estimate.CRM.Customer

    timestamps()
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 100)
  end

  def ai_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:openrouter_api_key, :openrouter_model, :openrouter_system_prompt])
    |> encrypt_api_key()
  end

  def smtp_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [
      :smtp_host,
      :smtp_port,
      :smtp_username,
      :smtp_password,
      :smtp_from_name,
      :smtp_from_email
    ])
    |> validate_format(:smtp_from_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_number(:smtp_port, greater_than: 0, less_than_or_equal_to: 65535)
    |> encrypt_smtp_password()
  end

  def security_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:enforce_2fa, :enforce_2fa_grace_period_days])
    |> validate_number(:enforce_2fa_grace_period_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 90
    )
  end

  @doc "Changeset for the MCP server settings (admin-managed)."
  def mcp_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:mcp_enabled])
    |> validate_required([:mcp_enabled])
  end

  def mcp_write_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:mcp_write_enabled])
    |> validate_required([:mcp_write_enabled])
  end

  defp encrypt_smtp_password(changeset) do
    case get_change(changeset, :smtp_password) do
      nil ->
        changeset

      "" ->
        changeset
        |> put_change(:encrypted_smtp_password, nil)
        |> put_change(:smtp_password_nonce, nil)
        |> put_change(:smtp_key_version, 1)

      password ->
        {:ok, nonce, ciphertext, version} = Encryption.encrypt(password)

        changeset
        |> put_change(:encrypted_smtp_password, ciphertext)
        |> put_change(:smtp_password_nonce, nonce)
        |> put_change(:smtp_key_version, version)
    end
  end

  defp encrypt_api_key(changeset) do
    case get_change(changeset, :openrouter_api_key) do
      nil ->
        changeset

      "" ->
        changeset
        |> put_change(:encrypted_openrouter_api_key, nil)
        |> put_change(:openrouter_api_key_nonce, nil)
        |> put_change(:openrouter_key_version, 1)

      key ->
        {:ok, nonce, ciphertext, version} = Encryption.encrypt(key)

        changeset
        |> put_change(:encrypted_openrouter_api_key, ciphertext)
        |> put_change(:openrouter_api_key_nonce, nonce)
        |> put_change(:openrouter_key_version, version)
    end
  end
end
