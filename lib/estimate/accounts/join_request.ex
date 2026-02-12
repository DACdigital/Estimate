defmodule Estimate.Accounts.JoinRequest do
  use Estimate.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved rejected)

  schema "join_requests" do
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime

    belongs_to :user, Estimate.Accounts.User
    belongs_to :organization, Estimate.Accounts.Organization
    belongs_to :reviewed_by, Estimate.Accounts.User

    timestamps()
  end

  def changeset(join_request, attrs) do
    join_request
    |> cast(attrs, [:user_id, :organization_id])
    |> validate_required([:user_id, :organization_id])
    |> unique_constraint([:user_id, :organization_id], name: :join_requests_pending_unique)
  end

  def review_changeset(join_request, status, reviewer_id)
      when status in ["approved", "rejected"] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    join_request
    |> change(status: status, reviewed_at: now, reviewed_by_id: reviewer_id)
  end

  def statuses, do: @statuses
end
