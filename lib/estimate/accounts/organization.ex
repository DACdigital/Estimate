defmodule Estimate.Accounts.Organization do
  use Estimate.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string

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
end
