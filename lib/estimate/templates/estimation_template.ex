defmodule Estimate.Templates.EstimationTemplate do
  use Estimate.Schema
  import Ecto.Changeset
  alias Estimate.ChangesetHelpers

  schema "estimation_templates" do
    field :name, :string
    field :description, :string

    belongs_to :organization, Estimate.Accounts.Organization

    has_many :epics, Estimate.Templates.EstimationTemplateEpic, preload_order: [asc: :position]

    timestamps()
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :organization_id])
    |> validate_required([:organization_id])
    |> ChangesetHelpers.validate_name(200)
  end
end
