defmodule Estimate.ChangesetHelpersTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  alias Estimate.ChangesetHelpers

  defmodule Named do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
    end
  end

  defp cs(attrs), do: cast(%Named{}, attrs, [:name])

  test "requires a name" do
    changeset = ChangesetHelpers.validate_name(cs(%{}), 200)
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects an empty name" do
    changeset = ChangesetHelpers.validate_name(cs(%{name: ""}), 200)
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "enforces the max length" do
    changeset = ChangesetHelpers.validate_name(cs(%{name: String.duplicate("x", 201)}), 200)
    assert %{name: [msg]} = errors_on(changeset)
    assert msg =~ "at most 200"
    assert ChangesetHelpers.validate_name(cs(%{name: String.duplicate("x", 200)}), 200).valid?
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
