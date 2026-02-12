defmodule Mix.Tasks.Search.Reindex do
  @moduledoc """
  Reindexes all searchable entities for all organizations.

  ## Usage

      mix search.reindex
      mix search.reindex --org ORG_ID
  """
  use Mix.Task

  @shortdoc "Reindex all entities for search"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [org: :string])

    case opts[:org] do
      nil ->
        reindex_all_orgs()

      org_id ->
        reindex_org(org_id)
    end
  end

  defp reindex_all_orgs do
    alias Estimate.Repo
    alias Estimate.Accounts.Organization

    orgs = Repo.all(Organization)
    total = length(orgs)

    Mix.shell().info("Reindexing #{total} organization(s)...")

    Enum.with_index(orgs, 1)
    |> Enum.each(fn {org, idx} ->
      Mix.shell().info("[#{idx}/#{total}] Reindexing #{org.name}...")
      Estimate.Search.reindex_all(org.id)
    end)

    Mix.shell().info("Done!")
  end

  defp reindex_org(org_id) do
    Mix.shell().info("Reindexing organization #{org_id}...")
    Estimate.Search.reindex_all(org_id)
    Mix.shell().info("Done!")
  end
end
