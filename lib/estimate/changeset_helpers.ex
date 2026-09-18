defmodule Estimate.ChangesetHelpers do
  @moduledoc """
  Cross-cutting changeset validations.
  """

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  alias Estimate.Repo

  @doc """
  Adds an error on `field` when the changed value does not reference a row of
  `schema` owned by `org_id`. Skips when the field is unchanged or nil.
  Runs inside the caller's RLS context: a row hidden by RLS also fails.
  """
  @spec validate_org_reference(Ecto.Changeset.t(), atom(), module(), Ecto.UUID.t()) ::
          Ecto.Changeset.t()
  def validate_org_reference(changeset, field, schema, org_id) do
    validate_change(changeset, field, fn ^field, id ->
      exists? =
        Repo.exists?(from(r in schema, where: r.id == ^id and r.organization_id == ^org_id))

      if exists?, do: [], else: [{field, "does not belong to this organization"}]
    end)
  end

  @doc """
  The project's standard `:name` rule: required and 1..`max` characters.
  Callers that require other fields call `validate_required/2` for those first.
  """
  @spec validate_name(Ecto.Changeset.t(), pos_integer()) :: Ecto.Changeset.t()
  def validate_name(changeset, max) when is_integer(max) and max > 0 do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: max)
  end
end
