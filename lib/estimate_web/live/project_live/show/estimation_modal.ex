defmodule EstimateWeb.ProjectLive.Show.EstimationModal do
  @moduledoc """
  New-estimation modal: source selection (fresh/copy/template/json), inline role
  editing, and creation dispatch across all four sources; also the JSON-import glue
  (schema download, agent-prompt copy, uploaded/pasted JSON validation).

  Reads: `:project`, `:org_id`, `:estimations`, `:role_templates`, `:currencies`,
  `:modal_roles`, `:modal_currency_id`, `:json_parsed`, `:can_edit_project`
  (via `Show.Authz.require_can_edit/2`).
  Writes: `:show_new_estimation_modal`, `:estimation_form`, `:estimation_source`,
  `:source_estimation_id`, `:modal_currency_id`, `:modal_currency`, `:modal_roles`,
  `:estimations`, plus the json assigns (via `JsonImportHelpers`).

  `init_modal_assigns/4` is the modal's mount-time initializer, called by
  `Show.mount/3` — co-located here since it shares `build_modal_roles_from_templates/2`
  with the modal handlers below.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.ProjectLive.Show.Authz
  import EstimateWeb.JsonImportHelpers

  alias Estimate.EstimationEngine

  ## Modal Init (called from Show.mount)

  def init_modal_assigns(socket, project, role_templates, estimation_templates) do
    socket
    |> assign(:show_new_estimation_modal, false)
    |> assign(:estimation_form, to_form(%{}, as: "estimation"))
    |> assign(:modal_currency_id, project.currency_id)
    |> assign(:modal_currency, project.currency)
    |> assign(:modal_roles, build_modal_roles_from_templates(role_templates, project.currency_id))
    |> assign(:estimation_source, "fresh")
    |> assign(:source_estimation_id, nil)
    |> assign(
      :selected_estimation_template_id,
      if(estimation_templates != [], do: hd(estimation_templates).id)
    )
  end

  ## Event Handlers

  def open_estimation_modal(socket, _params) do
    project = socket.assigns.project
    estimations = socket.assigns.estimations
    first_estimation_id = if Enum.any?(estimations), do: hd(estimations).id, else: nil

    {:noreply,
     socket
     |> assign(:show_new_estimation_modal, true)
     |> assign(:estimation_form, to_form(%{"name" => "", "description" => ""}, as: "estimation"))
     |> assign(:modal_currency_id, project.currency_id)
     |> assign(:modal_currency, project.currency)
     |> assign(
       :modal_roles,
       build_modal_roles_from_templates(socket.assigns.role_templates, project.currency_id)
     )
     |> assign(:estimation_source, "fresh")
     |> assign(:source_estimation_id, first_estimation_id)}
  end

  def set_estimation_source(socket, %{"source" => source}) do
    estimations = socket.assigns.estimations

    socket =
      if source == "copy" && Enum.any?(estimations) do
        first_est = hd(estimations)

        socket
        |> assign(
          :estimation_form,
          to_form(%{"name" => "Copy of #{first_est.name}", "description" => ""}, as: "estimation")
        )
        |> assign(:source_estimation_id, first_est.id)
        |> assign(:modal_currency_id, first_est.currency_id)
        |> assign(
          :modal_currency,
          Enum.find(socket.assigns.currencies, &(&1.id == first_est.currency_id))
        )
      else
        socket
        |> assign(
          :estimation_form,
          to_form(%{"name" => "", "description" => ""}, as: "estimation")
        )
        |> assign(:source_estimation_id, nil)
      end

    socket =
      socket
      |> assign(:estimation_source, source)
      |> clear_json()

    {:noreply, socket}
  end

  def close_estimation_modal(socket, _params) do
    {:noreply, assign(socket, :show_new_estimation_modal, false)}
  end

  def validate_estimation(socket, %{"json_input" => json_string} = params)
      when json_string != "" do
    socket
    |> do_validate_json(json_string)
    |> maybe_assign_modal_currency(params)
    |> update_modal_roles_from_params(params)
    |> then(&{:noreply, &1})
  end

  def validate_estimation(socket, params) do
    socket =
      if Map.get(params, "json_input") == "" do
        clear_json(socket)
      else
        socket
      end

    source_estimation_id = Map.get(params, "source_estimation_id")

    socket =
      socket
      |> maybe_assign_modal_currency(params)
      |> maybe_apply_copy_source(source_estimation_id)
      |> update_modal_roles_from_params(params)

    {:noreply, socket}
  end

  def remove_modal_role(socket, %{"temp-id" => temp_id}) do
    temp_id = String.to_integer(temp_id)
    roles = Enum.reject(socket.assigns.modal_roles, &(&1.temp_id == temp_id))
    {:noreply, assign(socket, :modal_roles, roles)}
  end

  def add_modal_role(socket, _params) do
    new_role = %{
      temp_id: System.unique_integer([:positive]),
      name: "",
      abbreviation: "",
      hourly_rate: Decimal.new(0),
      pm_overhead: Decimal.new(0),
      qa_overhead: Decimal.new(0),
      risk_buffer: Decimal.new(0),
      template_id: nil
    }

    {:noreply, assign(socket, :modal_roles, socket.assigns.modal_roles ++ [new_role])}
  end

  def reorder_modal_roles(socket, %{"ids" => ids}) do
    id_order = Enum.map(ids, &String.to_integer/1)
    roles_by_id = Map.new(socket.assigns.modal_roles, &{&1.temp_id, &1})
    reordered = Enum.map(id_order, &Map.fetch!(roles_by_id, &1))
    {:noreply, assign(socket, :modal_roles, reordered)}
  end

  def reset_modal_roles(socket, _params) do
    roles =
      build_modal_roles_from_templates(
        socket.assigns.role_templates,
        socket.assigns.modal_currency_id
      )

    {:noreply, assign(socket, :modal_roles, roles)}
  end

  def create_estimation(socket, %{"estimation" => estimation_params} = params) do
    socket = update_modal_roles_from_params(socket, params)

    require_can_edit(socket, fn ->
      source = Map.get(params, "source", "fresh")

      if source != "copy" && !roles_valid?(socket.assigns.modal_roles) do
        {:noreply, put_flash(socket, :error, "All roles must have a name and abbreviation")}
      else
        project = socket.assigns.project
        org_id = socket.assigns.org_id

        result = dispatch_create(source, estimation_params, params, socket, project, org_id)

        case result do
          {:ok, estimation} ->
            estimations = EstimationEngine.list_estimations(project.id)

            {:noreply,
             socket
             |> put_flash(
               :info,
               if(source == "copy", do: "Estimation copied", else: "Estimation created")
             )
             |> assign(:show_new_estimation_modal, false)
             |> assign(:estimations, estimations)
             |> push_navigate(
               to:
                 ~p"/org/#{socket.assigns.org_id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"
             )}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not create estimation")}
        end
      end
    end)
  end

  def json_file_uploaded(socket, %{"content" => content}) do
    {:noreply, do_validate_json(socket, content)}
  end

  def download_json_schema(socket, _params) do
    {:noreply, push_schema_download(socket)}
  end

  def copy_agent_prompt(socket, _params) do
    {:noreply, socket |> push_agent_prompt_copy() |> put_flash(:info, "Agent prompt copied")}
  end

  ## Private Helpers

  defp do_validate_json(socket, json_string) do
    socket = validate_json(socket, json_string)

    if socket.assigns.json_parsed do
      parsed = socket.assigns.json_parsed

      # Prefill form from parsed JSON
      form_data = %{
        "name" => parsed.estimation || "",
        "description" => parsed.description || ""
      }

      # Try to resolve currency code
      socket =
        if parsed.currency do
          currency =
            Enum.find(socket.assigns.currencies, fn c ->
              String.upcase(c.code) == String.upcase(parsed.currency)
            end)

          if currency do
            socket
            |> assign(:modal_currency_id, currency.id)
            |> assign(:modal_currency, currency)
          else
            socket
          end
        else
          socket
        end

      assign(socket, :estimation_form, to_form(form_data, as: "estimation"))
    else
      socket
    end
  end

  defp build_modal_roles_from_templates(role_templates, currency_id) do
    Enum.map(role_templates, fn template ->
      rate =
        Enum.find(template.rates, fn r -> to_string(r.currency_id) == to_string(currency_id) end)

      %{
        temp_id: System.unique_integer([:positive]),
        name: template.name,
        abbreviation: template.abbreviation,
        hourly_rate: if(rate, do: rate.hourly_rate, else: Decimal.new(0)),
        pm_overhead: template.pm_overhead,
        qa_overhead: template.qa_overhead,
        risk_buffer: template.risk_buffer,
        template_id: template.id
      }
    end)
  end

  defp dispatch_create("copy", estimation_params, params, socket, project, org_id) do
    source_estimation_id = Map.get(params, "source_estimation_id")
    name = estimation_params["name"]

    if source_estimation_id && name && name != "" do
      case fetch_authorized_estimation(socket, source_estimation_id) do
        {:ok, source_estimation} ->
          EstimationEngine.copy_estimation(source_estimation, name, project.id, org_id)

        {:error, _} ->
          {:error, :unauthorized}
      end
    else
      {:error, :invalid_params}
    end
  end

  defp dispatch_create("template", estimation_params, params, socket, project, org_id) do
    estimation_template_id = Map.get(params, "estimation_template_id")
    role_attrs = collect_role_attrs(socket.assigns.modal_roles)
    attrs = build_estimation_attrs(estimation_params, params, project, org_id)

    EstimationEngine.create_estimation_from_estimation_template(
      attrs,
      estimation_template_id,
      role_attrs
    )
  end

  defp dispatch_create("json", estimation_params, params, socket, project, org_id) do
    case socket.assigns.json_parsed do
      nil ->
        {:error, :no_json}

      parsed_json ->
        role_attrs = collect_role_attrs(socket.assigns.modal_roles)
        attrs = build_estimation_attrs(estimation_params, params, project, org_id)
        EstimationEngine.create_estimation_from_json(attrs, parsed_json, role_attrs)
    end
  end

  defp dispatch_create(_fresh, estimation_params, params, socket, project, org_id) do
    role_attrs = collect_role_attrs(socket.assigns.modal_roles)
    attrs = build_estimation_attrs(estimation_params, params, project, org_id)
    EstimationEngine.create_estimation_from_templates(attrs, role_attrs)
  end

  defp build_estimation_attrs(estimation_params, params, project, org_id) do
    currency_id = Map.get(params, "currency_id", project.currency_id)

    Map.merge(estimation_params, %{
      "project_id" => project.id,
      "currency_id" => currency_id,
      "organization_id" => org_id
    })
  end

  defp maybe_assign_modal_currency(socket, params) do
    currency_id = Map.get(params, "currency_id")

    if currency_id && currency_id != "" do
      currency = Enum.find(socket.assigns.currencies, &(to_string(&1.id) == currency_id))
      old_currency_id = socket.assigns.modal_currency_id

      socket
      |> assign(:modal_currency_id, currency_id)
      |> assign(:modal_currency, currency)
      |> maybe_update_modal_role_rates(old_currency_id, currency_id)
    else
      socket
    end
  end

  defp maybe_apply_copy_source(socket, source_estimation_id)
       when is_nil(source_estimation_id) or source_estimation_id == "",
       do: socket

  defp maybe_apply_copy_source(socket, source_estimation_id) do
    case Enum.find(socket.assigns.estimations, &(to_string(&1.id) == source_estimation_id)) do
      nil ->
        socket

      est ->
        socket
        |> assign(:source_estimation_id, source_estimation_id)
        |> assign(
          :estimation_form,
          to_form(%{"name" => "Copy of #{est.name}", "description" => ""}, as: "estimation")
        )
        |> assign(:modal_currency_id, est.currency_id)
        |> assign(
          :modal_currency,
          Enum.find(socket.assigns.currencies, &(&1.id == est.currency_id))
        )
    end
  end

  defp update_modal_roles_from_params(socket, params) do
    case Map.get(params, "roles") do
      nil ->
        socket

      roles_params when is_map(roles_params) ->
        updated =
          Enum.map(socket.assigns.modal_roles, fn role ->
            case Map.get(roles_params, to_string(role.temp_id)) do
              nil ->
                role

              fields ->
                role
                |> Map.put(:name, Map.get(fields, "name", role.name))
                |> Map.put(:abbreviation, Map.get(fields, "abbreviation", role.abbreviation))
                |> Map.put(
                  :hourly_rate,
                  parse_decimal(Map.get(fields, "hourly_rate"), role.hourly_rate)
                )
            end
          end)

        assign(socket, :modal_roles, updated)
    end
  end

  defp maybe_update_modal_role_rates(socket, old_currency_id, new_currency_id)
       when old_currency_id == new_currency_id,
       do: socket

  defp maybe_update_modal_role_rates(socket, _old, new_currency_id) do
    templates_by_id =
      Map.new(socket.assigns.role_templates, &{&1.id, &1})

    updated =
      Enum.map(socket.assigns.modal_roles, fn role ->
        case role.template_id && Map.get(templates_by_id, role.template_id) do
          nil ->
            role

          template ->
            rate =
              Enum.find(template.rates, fn r ->
                to_string(r.currency_id) == to_string(new_currency_id)
              end)

            %{role | hourly_rate: if(rate, do: rate.hourly_rate, else: Decimal.new(0))}
        end
      end)

    assign(socket, :modal_roles, updated)
  end

  defp collect_role_attrs(modal_roles) do
    Enum.map(modal_roles, fn role ->
      %{
        name: role.name,
        abbreviation: role.abbreviation,
        hourly_rate: role.hourly_rate,
        pm_overhead: role[:pm_overhead] || Decimal.new(0),
        qa_overhead: role[:qa_overhead] || Decimal.new(0),
        risk_buffer: role[:risk_buffer] || Decimal.new(0)
      }
    end)
  end

  defp roles_valid?(roles) do
    Enum.all?(roles, fn role ->
      String.trim(role.name || "") != "" && String.trim(role.abbreviation || "") != ""
    end)
  end

  defp parse_decimal(nil, default), do: default
  defp parse_decimal("", default), do: default

  defp parse_decimal(value, default) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> default
    end
  end

  defp parse_decimal(value, _default), do: value
end
