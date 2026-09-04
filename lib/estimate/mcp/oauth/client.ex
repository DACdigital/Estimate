defmodule Estimate.MCP.OAuth.Client do
  use Estimate.Schema

  import Ecto.Changeset

  alias Estimate.MCP.OAuth.Redirect

  schema "oauth_clients" do
    field :name, :string
    field :redirect_uris, {:array, :string}

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(client, attrs) do
    client
    |> cast(normalize(attrs), [:name, :redirect_uris])
    |> put_default_name()
    |> validate_required([:name, :redirect_uris])
    |> validate_length(:name, max: 100)
    |> validate_length(:redirect_uris, min: 1, max: 5)
    |> validate_change(:redirect_uris, fn :redirect_uris, uris ->
      if Enum.all?(uris, &Redirect.valid_for_registration?/1),
        do: [],
        else: [redirect_uris: "must be https or loopback http URIs"]
    end)
    |> validate_change(:redirect_uris, fn :redirect_uris, uris ->
      if Enum.all?(uris, &(String.length(&1) <= 2048)),
        do: [],
        else: [redirect_uris: "URIs must be at most 2048 characters"]
    end)
  end

  # DCR (RFC 7591) JSON uses "client_name"; the schema field is :name.
  defp normalize(%{"client_name" => name} = attrs), do: Map.put(attrs, "name", name)
  defp normalize(attrs), do: attrs

  defp put_default_name(changeset) do
    case get_field(changeset, :name) do
      nil -> put_change(changeset, :name, "MCP Client")
      _ -> changeset
    end
  end
end
