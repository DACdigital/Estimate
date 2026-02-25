defmodule Estimate.Search do
  @moduledoc """
  Full-text search context using PostgreSQL tsvector + pg_trgm.
  """

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.Search.SearchIndex

  @min_query_length 2
  @max_query_length 200
  @default_limit 8

  @doc """
  Searches across all indexed entities for the given organization.
  Returns list of results with type, id, title, subtitle, path_ids, and rank.
  """
  def search(org_id, query, opts \\ []) do
    Repo.ensure_org_context(fn ->
      query = query |> String.trim() |> String.slice(0, @max_query_length)

      if String.length(query) < @min_query_length do
        []
      else
        limit = Keyword.get(opts, :limit, @default_limit)
        types = Keyword.get(opts, :types, nil)

        # Prepare query for prefix matching: "impl" -> "impl:*"
        ts_query = prepare_ts_query(query)

        base_query =
          from(s in SearchIndex,
            where: s.organization_id == ^org_id,
            select: %{
              type: s.searchable_type,
              id: s.searchable_id,
              title: s.title,
              subtitle: s.subtitle,
              path_ids: s.path_ids,
              # Combined ranking: ts_rank for relevance + similarity for typo tolerance
              rank:
                fragment(
                  "ts_rank(search_vector, to_tsquery('english', ?)) + similarity(content, ?) AS rank",
                  ^ts_query,
                  ^query
                )
            },
            where:
              fragment(
                "search_vector @@ to_tsquery('english', ?) OR similarity(content, ?) > 0.1",
                ^ts_query,
                ^query
              ),
            order_by: [desc: fragment("rank")],
            limit: ^limit
          )

        base_query
        |> maybe_filter_types(types)
        |> Repo.all()
      end
    end)
  end

  defp maybe_filter_types(query, nil), do: query
  defp maybe_filter_types(query, []), do: query

  defp maybe_filter_types(query, types) when is_list(types) do
    from(s in query, where: s.searchable_type in ^types)
  end

  defp prepare_ts_query(query) do
    query
    |> String.replace(~r/[^a-zA-Z0-9\s]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn word -> "#{word}:*" end)
    |> Enum.join(" & ")
    |> case do
      "" -> "empty"
      result -> result
    end
  end

  ## Indexing functions

  @doc """
  Indexes a customer for search.
  """
  def index_customer(%{id: id, organization_id: org_id, name: name} = customer) do
    Repo.ensure_org_context(fn ->
      content = build_customer_content(customer)

      upsert_index(%{
        organization_id: org_id,
        searchable_type: "customer",
        searchable_id: id,
        title: name,
        subtitle: customer.key,
        path_ids: %{customer_id: id},
        content: content
      })
    end)
  end

  defp build_customer_content(customer) do
    [
      customer.name,
      customer.key,
      customer.country,
      customer.description
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Indexes a project for search. Includes customer name in content.
  """
  def index_project(%{id: id, customer: customer} = project) when not is_nil(customer) do
    Repo.ensure_org_context(fn ->
      content = build_project_content(project)

      upsert_index(%{
        organization_id: customer.organization_id,
        searchable_type: "project",
        searchable_id: id,
        title: project.name,
        subtitle: customer.name,
        path_ids: %{customer_id: customer.id, project_id: id},
        content: content
      })
    end)
  end

  def index_project(%{id: _id, customer_id: customer_id} = project) do
    Repo.ensure_org_context(fn ->
      # Load customer if not preloaded
      customer = Repo.get!(Estimate.CRM.Customer, customer_id)
      index_project(%{project | customer: customer})
    end)
  end

  defp build_project_content(project) do
    [
      project.name,
      project.key,
      project.short_description,
      project.detailed_description,
      project.customer.name,
      project.customer.key
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Indexes an estimation for search. Includes project, customer, and ALL task names.
  """
  def index_estimation(%{id: id, project: project} = estimation) when not is_nil(project) do
    Repo.ensure_org_context(fn ->
      # Ensure customer is loaded
      project =
        if is_nil(project.customer) do
          Repo.preload(project, :customer)
        else
          project
        end

      # Load tasks via epics
      estimation = Repo.preload(estimation, [epics: :tasks], force: true)
      content = build_estimation_content(estimation, project)

      upsert_index(%{
        organization_id: project.customer.organization_id,
        searchable_type: "estimation",
        searchable_id: id,
        title: estimation.name,
        subtitle: "#{project.customer.name} / #{project.name}",
        path_ids: %{
          customer_id: project.customer.id,
          project_id: project.id,
          estimation_id: id
        },
        content: content
      })
    end)
  end

  def index_estimation(%{id: _id, project_id: project_id} = estimation) do
    Repo.ensure_org_context(fn ->
      # Load project with customer if not preloaded
      project = Repo.get!(Estimate.Portfolio.Project, project_id) |> Repo.preload(:customer)
      index_estimation(%{estimation | project: project})
    end)
  end

  defp build_estimation_content(estimation, project) do
    task_names =
      estimation.epics
      |> Enum.flat_map(& &1.tasks)
      |> Enum.map(& &1.name)

    epic_names = Enum.map(estimation.epics, & &1.name)

    [
      estimation.name,
      estimation.description,
      project.name,
      project.key,
      project.customer.name,
      project.customer.key
      | epic_names ++ task_names
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc """
  Removes an entry from the search index.
  """
  def remove_index(type, id) do
    Repo.ensure_org_context(fn ->
      from(s in SearchIndex,
        where: s.searchable_type == ^type and s.searchable_id == ^id
      )
      |> Repo.delete_all()

      :ok
    end)
  end

  @doc """
  Removes search index entries for all estimations belonging to a project.
  Must be called BEFORE deleting the project (cascade would remove estimation rows).
  """
  def remove_index_for_project(project_id) do
    Repo.ensure_org_context(fn ->
      from(s in SearchIndex,
        where:
          s.searchable_type == "estimation" and
            s.searchable_id in subquery(
              from(e in Estimate.EstimationEngine.Estimation,
                where: e.project_id == ^project_id,
                select: e.id
              )
            )
      )
      |> Repo.delete_all()

      :ok
    end)
  end

  @doc """
  Removes search index entries for all projects and estimations belonging to a customer.
  Must be called BEFORE deleting the customer (cascade would remove child rows).
  """
  def remove_index_for_customer(customer_id) do
    Repo.ensure_org_context(fn ->
      project_ids =
        from(p in Estimate.Portfolio.Project,
          where: p.customer_id == ^customer_id,
          select: p.id
        )

      from(s in SearchIndex,
        where:
          (s.searchable_type == "project" and s.searchable_id in subquery(project_ids)) or
            (s.searchable_type == "estimation" and
               s.searchable_id in subquery(
                 from(e in Estimate.EstimationEngine.Estimation,
                   where: e.project_id in subquery(project_ids),
                   select: e.id
                 )
               ))
      )
      |> Repo.delete_all()

      :ok
    end)
  end

  defp upsert_index(attrs) do
    %SearchIndex{}
    |> SearchIndex.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:title, :subtitle, :path_ids, :content, :updated_at]},
      conflict_target: [:searchable_type, :searchable_id]
    )
  end

  ## Bulk reindex

  @doc """
  Reindexes all entities for an organization.
  """
  def reindex_all(org_id) do
    Repo.ensure_org_context(fn ->
      reindex_customers(org_id)
      reindex_projects(org_id)
      reindex_estimations(org_id)
      :ok
    end)
  end

  defp reindex_customers(org_id) do
    from(c in Estimate.CRM.Customer, where: c.organization_id == ^org_id)
    |> Repo.all()
    |> Enum.each(&index_customer/1)
  end

  defp reindex_projects(org_id) do
    from(p in Estimate.Portfolio.Project,
      join: c in assoc(p, :customer),
      where: c.organization_id == ^org_id,
      preload: [:customer]
    )
    |> Repo.all()
    |> Enum.each(&index_project/1)
  end

  defp reindex_estimations(org_id) do
    from(e in Estimate.EstimationEngine.Estimation,
      join: p in assoc(e, :project),
      join: c in assoc(p, :customer),
      where: c.organization_id == ^org_id and is_nil(e.deleted_at),
      preload: [project: [:customer]]
    )
    |> Repo.all()
    |> Enum.each(&index_estimation/1)
  end
end
