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

  def estimation_tree(est) do
    alias Estimate.EstimationEngine.Calculator

    %{
      id: est.id,
      name: est.name,
      description: est.description,
      is_current: est.is_current,
      currency: assoc_code(est.currency),
      updated_at: datetime(est.updated_at),
      roles: Enum.map(est.roles, &estimation_role/1),
      epics: Enum.map(est.epics, &epic/1),
      totals: %{
        total_hours: decimal(Calculator.calc_total_hours(est.epics)),
        total_hours_with_overhead:
          decimal(Calculator.calc_total_with_overhead_hours(est.epics, est.roles)),
        base_cost: decimal(Calculator.calc_base_cost(est.epics, est.roles)),
        grand_total_with_overhead:
          decimal(Calculator.grand_total_with_overhead(est.epics, est.roles))
      }
    }
  end

  def estimation_role(r) do
    %{
      id: r.id,
      name: r.name,
      abbreviation: r.abbreviation,
      hourly_rate: decimal(r.hourly_rate),
      position: r.position,
      pm_overhead: decimal(r.pm_overhead),
      qa_overhead: decimal(r.qa_overhead),
      risk_buffer: decimal(r.risk_buffer)
    }
  end

  def epic(e) do
    %{
      id: e.id,
      name: e.name,
      description: e.description,
      position: e.position,
      tasks: Enum.map(e.tasks, &task/1)
    }
  end

  def task(t) do
    %{
      id: t.id,
      name: t.name,
      description: t.description,
      position: t.position,
      priority: t.priority,
      estimates:
        Enum.map(t.estimates, fn te ->
          %{role_id: te.estimation_role_id, hours: decimal(te.hours)}
        end)
    }
  end

  def decimal(nil), do: nil
  def decimal(%Decimal{} = d), do: Decimal.to_string(d)

  def datetime(nil), do: nil
  def datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def assoc_code(%{code: code}), do: code
  def assoc_code(_), do: nil
end
