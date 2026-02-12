defmodule Estimate.Accounts.RoleTemplate do
  use Estimate.Schema
  import Ecto.Changeset

  schema "role_templates" do
    field :name, :string
    field :abbreviation, :string
    field :position, :integer, default: 0
    field :pm_overhead, :decimal, default: Decimal.new(0)
    field :qa_overhead, :decimal, default: Decimal.new(0)
    field :risk_buffer, :decimal, default: Decimal.new(0)

    belongs_to :organization, Estimate.Accounts.Organization
    has_many :rates, Estimate.Accounts.RoleTemplateRate

    timestamps()
  end

  def changeset(role_template, attrs) do
    role_template
    |> cast(attrs, [
      :name,
      :abbreviation,
      :position,
      :pm_overhead,
      :qa_overhead,
      :risk_buffer,
      :organization_id
    ])
    |> validate_required([:name, :abbreviation, :organization_id])
    |> validate_length(:abbreviation, min: 1, max: 5)
    |> validate_number(:pm_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:qa_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:risk_buffer, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint([:organization_id, :abbreviation])
    |> update_change(:abbreviation, &String.upcase/1)
  end

  @default_templates [
    %{
      name: "Business Analyst",
      abbreviation: "BA",
      position: 0,
      default_rate: 100,
      pm_overhead: 15,
      qa_overhead: 10,
      risk_buffer: 10
    },
    %{
      name: "UX Designer",
      abbreviation: "UX",
      position: 1,
      default_rate: 100,
      pm_overhead: 15,
      qa_overhead: 10,
      risk_buffer: 10
    },
    %{
      name: "Mobile Developer",
      abbreviation: "MO",
      position: 2,
      default_rate: 120,
      pm_overhead: 20,
      qa_overhead: 15,
      risk_buffer: 15
    },
    %{
      name: "Backend Developer",
      abbreviation: "BE",
      position: 3,
      default_rate: 120,
      pm_overhead: 20,
      qa_overhead: 15,
      risk_buffer: 15
    },
    %{
      name: "Frontend Developer",
      abbreviation: "FE",
      position: 4,
      default_rate: 110,
      pm_overhead: 20,
      qa_overhead: 15,
      risk_buffer: 15
    },
    %{
      name: "DevOps Engineer",
      abbreviation: "DO",
      position: 5,
      default_rate: 130,
      pm_overhead: 15,
      qa_overhead: 10,
      risk_buffer: 15
    },
    %{
      name: "AI Engineer",
      abbreviation: "AI",
      position: 6,
      default_rate: 150,
      pm_overhead: 20,
      qa_overhead: 15,
      risk_buffer: 20
    },
    %{
      name: "Solution Architect",
      abbreviation: "SA",
      position: 7,
      default_rate: 150,
      pm_overhead: 10,
      qa_overhead: 5,
      risk_buffer: 10
    }
  ]

  def default_templates, do: @default_templates
end
