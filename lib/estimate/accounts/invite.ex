defmodule Estimate.Accounts.Invite do
  use Estimate.Schema
  import Ecto.Changeset

  @rand_size 32
  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  schema "invites" do
    field :email, :string
    field :code, :string
    field :token, :string
    field :role, :string, default: "member"
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :organization, Estimate.Accounts.Organization
    belongs_to :invited_by, Estimate.Accounts.User

    timestamps()
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:email, :role, :organization_id, :invited_by_id])
    |> validate_required([:email, :role, :organization_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_inclusion(:role, Estimate.Accounts.Membership.roles())
    |> put_token()
    |> put_expires_at()
    |> unique_constraint(:token)
  end

  def code_changeset(invite, attrs) do
    invite
    |> cast(attrs, [:role, :organization_id, :invited_by_id])
    |> validate_required([:role, :organization_id])
    |> validate_inclusion(:role, Estimate.Accounts.Membership.roles())
    |> put_code()
    |> put_token()
    |> put_expires_at()
    |> unique_constraint(:token)
  end

  defp put_code(changeset) do
    if changeset.valid? do
      put_change(changeset, :code, generate_code())
    else
      changeset
    end
  end

  def generate_code(length \\ 8) do
    for _ <- 1..length, into: "" do
      <<Enum.random(@code_alphabet)>>
    end
  end

  defp put_token(changeset) do
    if changeset.valid? do
      token = :crypto.strong_rand_bytes(@rand_size) |> Base.url_encode64(padding: false)
      put_change(changeset, :token, token)
    else
      changeset
    end
  end

  defp put_expires_at(changeset) do
    if changeset.valid? do
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(7, :day)
        |> DateTime.truncate(:second)

      put_change(changeset, :expires_at, expires_at)
    else
      changeset
    end
  end

  def valid?(%__MODULE__{expires_at: expires_at, accepted_at: nil}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  def valid?(_), do: false

  def accept_changeset(invite) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(invite, accepted_at: now)
  end
end
