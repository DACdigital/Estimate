defmodule Estimate.MCP.OAuth do
  @moduledoc """
  Minimal OAuth 2.1 authorization server backing the MCP endpoint:
  dynamic client registration, PKCE authorization codes, rotating
  refresh-token families. All DB ops run via `Repo.without_rls/1` —
  OAuth requests carry no org RLS context; identity comes from the
  authenticated session (authorize) or presented token hashes.
  """

  alias Estimate.MCP.OAuth.Client
  alias Estimate.Repo

  def register_client(attrs) when is_map(attrs) do
    changeset = Client.registration_changeset(%Client{}, attrs)
    Repo.without_rls(fn -> Repo.insert(changeset) end)
  end

  def get_client(client_id) do
    Repo.without_rls(fn -> Repo.get(Client, client_id) end)
  rescue
    Ecto.Query.CastError -> nil
  end
end
