defmodule Estimate.Accounts.Organization do
  use Estimate.Schema
  import Ecto.Changeset

  alias Estimate.Encryption

  schema "organizations" do
    field :name, :string
    field :encrypted_openrouter_api_key, :binary
    field :openrouter_api_key_nonce, :binary
    field :openrouter_model, :string
    field :openrouter_system_prompt, :string

    # Virtual — for form input only, never persisted
    field :openrouter_api_key, :string, virtual: true

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

  defp encrypt_api_key(changeset) do
    case get_change(changeset, :openrouter_api_key) do
      nil ->
        changeset

      "" ->
        changeset
        |> put_change(:encrypted_openrouter_api_key, nil)
        |> put_change(:openrouter_api_key_nonce, nil)

      key ->
        {:ok, nonce, ciphertext} = Encryption.encrypt(key)

        changeset
        |> put_change(:encrypted_openrouter_api_key, ciphertext)
        |> put_change(:openrouter_api_key_nonce, nonce)
    end
  end
end
