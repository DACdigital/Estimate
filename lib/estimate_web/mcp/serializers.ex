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

  def decimal(nil), do: nil
  def decimal(%Decimal{} = d), do: Decimal.to_string(d)

  def datetime(nil), do: nil
  def datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def assoc_code(%{code: code}), do: code
  def assoc_code(_), do: nil
end
