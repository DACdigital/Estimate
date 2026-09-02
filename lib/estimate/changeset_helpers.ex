defmodule Estimate.ChangesetHelpers do
  @moduledoc """
  Cross-cutting changeset validations that need the database.
  """

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  alias Estimate.Repo

  @doc """
  Adds an error on `field` when the changed value does not reference a row of
  `schema` owned by `org_id`. Skips when the field is unchanged or nil.
  Runs inside the caller's RLS context: a row hidden by RLS also fails.
  """
  def validate_org_reference(changeset, field, schema, org_id) do
    validate_change(changeset, field, fn ^field, id ->
      exists? =
        Repo.exists?(from(r in schema, where: r.id == ^id and r.organization_id == ^org_id))

      if exists?, do: [], else: [{field, "does not belong to this organization"}]
    end)
  end
end
