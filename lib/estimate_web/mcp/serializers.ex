defmodule EstimateWeb.MCP.Serializers do
  @moduledoc """
  Structs → JSON-native maps for MCP tool responses. Only strings,
  numbers, booleans, nil, lists, maps — Decimal and DateTime are
  stringified so any JSON encoder can handle them.
  """

  def customer(c) do
    %{
      id: c.id,
      key: c.key,
      name: c.name,
      country: c.country,
      website_url: c.website_url,
      description: c.description,
      currency: assoc_code(c.default_currency),
      project_count: if(is_integer(c.project_count), do: c.project_count),
      updated_at: datetime(c.updated_at)
    }
  end

  def search_hit(hit) do
    %{type: hit.type, id: hit.id, title: hit.title, subtitle: hit.subtitle}
  end

  def project(p) do
    %{
      id: p.id,
      key: p.key,
      name: p.name,
      status: p.status,
      short_description: p.short_description,
      repository_url: p.repository_url,
      customer: project_customer(p.customer),
      currency: assoc_code(p.currency),
      updated_at: datetime(p.updated_at)
    }
  end

  def project_role(r) do
    %{
      id: r.id,
      name: r.name,
      abbreviation: r.abbreviation,
      hourly_rate: decimal(r.hourly_rate),
      pm_overhead: decimal(r.pm_overhead),
      qa_overhead: decimal(r.qa_overhead),
      risk_buffer: decimal(r.risk_buffer)
    }
  end

  def estimation_summary(e) do
    %{id: e.id, name: e.name, is_current: e.is_current, updated_at: datetime(e.updated_at)}
  end

  defp project_customer(%{id: id, name: name}), do: %{id: id, name: name}
  defp project_customer(_), do: nil

  def decimal(nil), do: nil
  def decimal(%Decimal{} = d), do: Decimal.to_string(d)

  def datetime(nil), do: nil
  def datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def assoc_code(%{code: code}), do: code
  def assoc_code(_), do: nil
end
