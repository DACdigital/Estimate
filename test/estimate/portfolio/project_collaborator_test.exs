defmodule Estimate.Portfolio.ProjectCollaboratorTest do
  use ExUnit.Case, async: true
  alias Estimate.Portfolio.ProjectCollaborator

  test "edit_roles is the single source for editing collaborator roles" do
    assert Enum.all?(ProjectCollaborator.edit_roles(), &(&1 in ProjectCollaborator.roles()))
    refute "viewer" in ProjectCollaborator.edit_roles()
  end
end
