defmodule Estimate.Accounts.Membership do
  use Estimate.Schema
  import Ecto.Changeset

  @roles ~w(owner admin member)

  schema "memberships" do
    field :role, :string, default: "member"
    field :totp_required_by, :utc_datetime

    belongs_to :user, Estimate.Accounts.User
    belongs_to :organization, Estimate.Accounts.Organization

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :user_id, :organization_id])
    |> validate_required([:role, :user_id, :organization_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :organization_id])
  end

  def roles, do: @roles
  def admin_roles, do: ~w(owner admin)
  def assignable_roles, do: ~w(admin member)
end
