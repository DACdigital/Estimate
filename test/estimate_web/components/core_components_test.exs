defmodule EstimateWeb.CoreComponentsTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EstimateWeb.CoreComponents

  describe "badge/1" do
    test "variant :neutral renders bg-base-200 text-base-content/60" do
      html =
        render_component(&CoreComponents.badge/1, %{
          variant: :neutral,
          inner_block: [%{inner_block: fn _, _ -> "You" end}]
        })

      assert html =~ "bg-base-200 text-base-content/60"
      assert html =~ "rounded-full"
      assert html =~ "You"
    end

    test "variant :muted renders bg-base-200 text-base-content/40" do
      html =
        render_component(&CoreComponents.badge/1, %{
          variant: :muted,
          inner_block: [%{inner_block: fn _, _ -> "No 2FA" end}]
        })

      assert html =~ "bg-base-200 text-base-content/40"
      assert html =~ "No 2FA"
    end

    test "variant :success renders bg-success/10 text-success" do
      html =
        render_component(&CoreComponents.badge/1, %{
          variant: :success,
          inner_block: [%{inner_block: fn _, _ -> "2FA" end}]
        })

      assert html =~ "bg-success/10 text-success"
      assert html =~ "rounded-full"
      assert html =~ "2FA"
    end

    test "variant defaults to :neutral when omitted" do
      html =
        render_component(&CoreComponents.badge/1, %{
          inner_block: [%{inner_block: fn _, _ -> "Default" end}]
        })

      assert html =~ "bg-base-200 text-base-content/60"
    end
  end
end
