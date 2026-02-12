defmodule Estimate.Search.SearchIndex do
  use Estimate.Schema
  import Ecto.Changeset

  @types ~w(customer project estimation)

  schema "search_index" do
    field :searchable_type, :string
    field :searchable_id, :binary_id
    field :title, :string
    field :subtitle, :string
    field :path_ids, :map, default: %{}
    field :content, :string
    field :search_vector, :any, virtual: true

    belongs_to :organization, Estimate.Accounts.Organization

    timestamps()
  end

  def changeset(index, attrs) do
    index
    |> cast(attrs, [
      :organization_id,
      :searchable_type,
      :searchable_id,
      :title,
      :subtitle,
      :path_ids,
      :content
    ])
    |> validate_required([:organization_id, :searchable_type, :searchable_id, :title, :content])
    |> validate_inclusion(:searchable_type, @types)
    |> unique_constraint([:searchable_type, :searchable_id])
  end

  def types, do: @types
end
