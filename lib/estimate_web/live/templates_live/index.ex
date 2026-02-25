defmodule EstimateWeb.TemplatesLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Templates
  import EstimateWeb.Components.JsonImportComponent
  import EstimateWeb.JsonImportHelpers
  import EstimateWeb.LiveHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Estimation Templates</h1>
        <p class="mt-1 text-base-content/60">
          Reusable epic & task structures for new estimations
        </p>
      </div>

      <%!-- Template Cards --%>
      <div class="grid gap-4 mb-6">
        <%= for template <- @templates do %>
          <div class="bg-base-100 border border-base-300 rounded-xl p-5 hover:border-base-content/20 transition-colors group">
            <div class="flex items-start justify-between">
              <.link
                navigate={~p"/org/#{@org_id}/templates/#{template.id}"}
                class="flex-1 min-w-0"
              >
                <h3 class="text-base font-semibold text-base-content group-hover:text-base-content/80">
                  {template.name}
                </h3>
                <p :if={template.description} class="text-sm text-base-content/60 mt-1 line-clamp-2">
                  {template.description}
                </p>
                <div class="flex items-center gap-4 mt-3 text-xs text-base-content/40">
                  <span class="flex items-center gap-1">
                    <.icon name="hero-rectangle-stack" class="w-3.5 h-3.5" />
                    {length(template.epics)} epics
                  </span>
                  <span class="flex items-center gap-1">
                    <.icon name="hero-list-bullet" class="w-3.5 h-3.5" />
                    {Enum.sum(Enum.map(template.epics, fn e -> length(e.tasks) end))} tasks
                  </span>
                </div>
              </.link>
              <button
                :if={@is_admin}
                phx-click="confirm_delete"
                phx-value-id={template.id}
                class="p-1.5 text-base-content/40 hover:text-error opacity-0 group-hover:opacity-100 transition-all"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          </div>
        <% end %>

        <%= if Enum.empty?(@templates) do %>
          <div class="bg-base-100 border border-base-300 rounded-xl p-12 text-center">
            <.icon name="hero-rectangle-stack" class="w-12 h-12 text-base-content/30 mx-auto" />
            <p class="mt-3 text-base-content/60">No templates yet</p>
            <p class="text-sm text-base-content/40 mt-1">Create one below to get started</p>
          </div>
        <% end %>
      </div>

      <%!-- New Template --%>
      <div :if={@is_admin} class="bg-base-100 border border-base-300 rounded-xl">
        <div class="px-6 pt-4 pb-2">
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="set_creation_mode"
              phx-value-mode="manual"
              class={"px-3 py-2 text-sm font-medium rounded-lg border-2 transition-colors #{if @creation_mode == "manual", do: "border-neutral bg-neutral text-neutral-content", else: "border-base-300 text-base-content/70 hover:border-base-content/20"}"}
            >
              <.icon name="hero-plus" class="w-4 h-4 inline-block mr-1 -mt-0.5" /> Manual
            </button>
            <button
              type="button"
              phx-click="set_creation_mode"
              phx-value-mode="json"
              class={"px-3 py-2 text-sm font-medium rounded-lg border-2 transition-colors #{if @creation_mode == "json", do: "border-neutral bg-neutral text-neutral-content", else: "border-base-300 text-base-content/70 hover:border-base-content/20"}"}
            >
              <.icon name="hero-arrow-up-tray" class="w-4 h-4 inline-block mr-1 -mt-0.5" />
              Import JSON
            </button>
          </div>
        </div>

        <%= if @creation_mode == "manual" do %>
          <form phx-submit="create_template" class="px-6 py-4">
            <div class="flex items-center gap-3">
              <input
                type="text"
                name="name"
                value=""
                placeholder="New template name..."
                required
                class="flex-1 px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
              <button
                type="submit"
                class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
              >
                Create Template
              </button>
            </div>
          </form>
        <% else %>
          <form phx-submit="create_template_from_json" phx-change="validate_template_json" class="px-6 py-4 space-y-4">
            <.json_import_panel
              json_input={@json_input}
              json_error={@json_error}
              json_parsed={@json_parsed}
            />

            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Template Name</label>
              <input
                type="text"
                name="template_name"
                value={@template_name}
                placeholder="Template name (auto-filled from JSON)..."
                required
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>

            <div class="flex justify-end">
              <button
                type="submit"
                disabled={!@json_parsed}
                phx-disable-with="Importing..."
                class={"px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium #{if !@json_parsed, do: "opacity-50 cursor-not-allowed"}"}
              >
                Import Template
              </button>
            </div>
          </form>
        <% end %>
      </div>

      <.confirm_modal
        :if={@deleting_template}
        id="delete-template-modal"
        title="Delete Template"
        item_name={@deleting_template.name}
        confirm_event="delete_template"
        cancel_event="cancel_delete"
      />
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    templates = Templates.list_estimation_templates(socket.assigns.org_id)

    {:ok,
     socket
     |> assign(:page_title, "Templates")
     |> assign(:active_tab, :templates)
     |> assign(:templates, templates)
     |> assign(:is_admin, admin?(socket.assigns.current_membership))
     |> assign(:deleting_template, nil)
     |> assign(:creation_mode, "manual")
     |> assign(:template_name, "")
     |> init_json_assigns()}
  end

  @impl true
  def handle_event("set_creation_mode", %{"mode" => mode}, socket) do
    {:noreply,
     socket
     |> assign(:creation_mode, mode)
     |> assign(:template_name, "")
     |> clear_json()}
  end

  def handle_event("validate_template_json", %{"json_input" => json_string} = params, socket) do
    socket = validate_json(socket, json_string)

    # Auto-fill template name from parsed JSON if user hasn't overridden
    template_name = Map.get(params, "template_name", "")

    socket =
      if template_name == "" && socket.assigns.json_parsed do
        assign(socket, :template_name, socket.assigns.json_parsed.estimation || "")
      else
        assign(socket, :template_name, template_name)
      end

    {:noreply, socket}
  end

  def handle_event("validate_template_json", params, socket) do
    template_name = Map.get(params, "template_name", socket.assigns.template_name)

    socket =
      if Map.get(params, "json_input") == "" do
        clear_json(socket)
      else
        socket
      end

    {:noreply, assign(socket, :template_name, template_name)}
  end

  def handle_event("json_file_uploaded", %{"content" => content}, socket) do
    socket = validate_json(socket, content)

    socket =
      if socket.assigns.json_parsed do
        assign(socket, :template_name, socket.assigns.json_parsed.estimation || "")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("download_json_schema", _params, socket) do
    {:noreply, push_schema_download(socket)}
  end

  def handle_event("create_template_from_json", %{"template_name" => name}, socket) do
    require_admin(socket, fn ->
      parsed = socket.assigns.json_parsed

      if parsed do
        attrs = %{"name" => name, "description" => parsed.description}

        case Templates.create_template_from_json(socket.assigns.org_id, attrs, parsed) do
          {:ok, template} ->
            {:noreply,
             socket
             |> put_flash(:info, "Template imported")
             |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/templates/#{template.id}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not import template")}
        end
      else
        {:noreply, put_flash(socket, :error, "No valid JSON to import")}
      end
    end)
  end

  def handle_event("create_template", %{"name" => name}, socket) when name != "" do
    require_admin(socket, fn ->
      case Templates.create_estimation_template(socket.assigns.org_id, %{"name" => name}) do
        {:ok, template} ->
          {:noreply,
           socket
           |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/templates/#{template.id}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not create template")}
      end
    end)
  end

  def handle_event("create_template", _params, socket), do: {:noreply, socket}

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    template = Templates.get_estimation_template!(id, socket.assigns.org_id)
    {:noreply, assign(socket, :deleting_template, template)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_template, nil)}
  end

  def handle_event("delete_template", _params, socket) do
    require_admin(socket, fn ->
      template = socket.assigns.deleting_template

      case Templates.delete_estimation_template(template) do
        {:ok, _} ->
          templates = Templates.list_estimation_templates(socket.assigns.org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Template deleted")
           |> assign(:templates, templates)
           |> assign(:deleting_template, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not delete template")
           |> assign(:deleting_template, nil)}
      end
    end)
  end
end
