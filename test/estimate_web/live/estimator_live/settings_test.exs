defmodule EstimateWeb.EstimatorLive.SettingsTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.EstimationEngine
  alias Estimate.Organizations.Currencies

  setup :setup_estimator

  defp role_params(role, overrides) do
    Map.merge(
      %{
        "name" => role.name,
        "abbreviation" => role.abbreviation,
        "hourly_rate" => "100",
        "pm_overhead" => "10",
        "qa_overhead" => "5",
        "risk_buffer" => "0"
      },
      overrides
    )
  end

  test "open_settings opens the settings modal", ctx do
    render_click(ctx.lv, "open_settings", %{})
    assert assigns(ctx.lv).modal == :settings
    assert render(ctx.lv) =~ ~s(id="settings-form")
  end

  test "save_settings updates name, currency and roles, then closes the modal", ctx do
    # NOTE: brief used "EUR", but the org's default currency seed already includes
    # EUR/USD/GBP/PLN (Estimate.Accounts.Currency.default_currencies/0), which made
    # create_currency/2 fail with a uniqueness error. Using a code outside that set.
    {:ok, chf} =
      Currencies.create_currency(ctx.org.id, %{
        "code" => "CHF",
        "name" => "Swiss Franc",
        "symbol" => "CHF"
      })

    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "save_settings", %{
        "name" => "Renamed",
        "currency_id" => chf.id,
        "roles" => %{
          ctx.role.id => role_params(ctx.role, %{"name" => "Lead Dev", "hourly_rate" => "200"})
        }
      })

    assert html =~ "Settings saved"
    a = assigns(ctx.lv)
    assert a.modal == nil
    assert a.estimation.name == "Renamed"
    assert a.estimation.currency_id == chf.id
    role = Enum.find(a.estimation.roles, &(&1.id == ctx.role.id))
    assert role.name == "Lead Dev"
    assert Decimal.equal?(role.hourly_rate, Decimal.new(200))
    assert Decimal.equal?(role.pm_overhead, Decimal.new(10))
  end

  test "save_settings with a role from another estimation flashes and changes nothing", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "save_settings", %{
        "name" => "Hijack",
        "currency_id" => ctx.est.currency_id,
        "roles" => %{other_role.id => role_params(other_role, %{"name" => "PWNED"})}
      })

    assert html =~ "Could not update roles"
    assert assigns(ctx.lv).modal == :settings
    assert EstimationEngine.get_role!(other_role.id, ctx.org.id).name == other_role.name
    assert refetch(ctx.est, ctx.org).name == ctx.est.name
  end

  test "save_settings with an invalid estimation name flashes Could not save settings", ctx do
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "save_settings", %{
        "name" => "",
        "currency_id" => ctx.est.currency_id,
        "roles" => %{}
      })

    assert html =~ "Could not save settings"
    assert assigns(ctx.lv).modal == :settings
    assert refetch(ctx.est, ctx.org).name == ctx.est.name
  end

  test "add_estimation_role appends a zero-rate role with upcased abbreviation", ctx do
    before = length(ctx.est.roles)
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "add_estimation_role", %{
        "new_role_name" => "Designer",
        "new_role_abbr" => "ux"
      })

    assert html =~ "Role added"
    roles = assigns(ctx.lv).estimation.roles
    assert length(roles) == before + 1
    new_role = List.last(roles)
    assert new_role.name == "Designer" and new_role.abbreviation == "UX"
    assert new_role.position == before
    assert Decimal.equal?(new_role.hourly_rate, Decimal.new(0))
  end

  test "add_estimation_role with an empty name or abbreviation is a no-op", ctx do
    before = length(ctx.est.roles)
    render_submit(ctx.lv, "add_estimation_role", %{"new_role_name" => "", "new_role_abbr" => "X"})
    render_submit(ctx.lv, "add_estimation_role", %{"new_role_name" => "X", "new_role_abbr" => ""})
    assert length(refetch(ctx.est, ctx.org).roles) == before
  end

  test "confirm_delete_role / cancel_delete_role toggle deleting_role_id", ctx do
    render_click(ctx.lv, "confirm_delete_role", %{"id" => ctx.role.id})
    assert assigns(ctx.lv).deleting_role_id == ctx.role.id

    render_click(ctx.lv, "cancel_delete_role", %{})
    assert assigns(ctx.lv).deleting_role_id == nil
  end

  test "delete_estimation_role deletes the confirmed role and reloads", ctx do
    before = length(ctx.est.roles)
    render_click(ctx.lv, "confirm_delete_role", %{"id" => ctx.role.id})
    html = render_click(ctx.lv, "delete_estimation_role", %{})

    assert html =~ "Role deleted"
    a = assigns(ctx.lv)
    assert a.deleting_role_id == nil
    assert length(a.estimation.roles) == before - 1
    refute Enum.any?(a.estimation.roles, &(&1.id == ctx.role.id))
  end

  test "delete_estimation_role with nothing confirmed is a no-op", ctx do
    before = length(ctx.est.roles)
    render_click(ctx.lv, "delete_estimation_role", %{})
    assert length(refetch(ctx.est, ctx.org).roles) == before
  end

  test "delete_estimation_role for a role from another estimation flashes Not authorized", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)
    render_click(ctx.lv, "confirm_delete_role", %{"id" => other_role.id})

    html = render_click(ctx.lv, "delete_estimation_role", %{})
    assert html =~ "Not authorized"
    assert EstimationEngine.get_role!(other_role.id, ctx.org.id)
  end

  test "reorder_roles persists the order (no in-memory reload; the broadcast does it)", ctx do
    [r1, r2 | rest] = ctx.est.roles
    ids = Enum.map([r2, r1 | rest], & &1.id)

    render_click(ctx.lv, "reorder_roles", %{"ids" => ids})
    assert Enum.map(refetch(ctx.est, ctx.org).roles, & &1.id) == ids
    # the LV's own broadcast reaches it and reloads
    render(ctx.lv)
    assert Enum.map(assigns(ctx.lv).estimation.roles, & &1.id) == ids
  end

  describe "viewer" do
    setup ctx do
      {_u, {:ok, lv, _}} = mount_as("viewer", ctx)
      %{vlv: lv}
    end

    test "settings and role mutations are denied", ctx do
      for {event, params} <- [
            {"open_settings", %{}},
            {"save_settings",
             %{"name" => "X", "currency_id" => ctx.est.currency_id, "roles" => %{}}},
            {"add_estimation_role", %{"new_role_name" => "N", "new_role_abbr" => "N"}},
            {"confirm_delete_role", %{"id" => ctx.role.id}},
            {"delete_estimation_role", %{}},
            {"reorder_roles", %{"ids" => Enum.map(ctx.est.roles, & &1.id)}}
          ] do
        html = render_click(ctx.vlv, event, params)
        assert html =~ "You don&#39;t have edit access", event
      end

      assert assigns(ctx.vlv).modal == nil
      assert refetch(ctx.est, ctx.org).name == ctx.est.name
    end
  end
end
