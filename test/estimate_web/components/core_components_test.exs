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

  describe "avatar/1" do
    test ":customer and :project share the entity palette deterministically" do
      customer =
        render_component(&CoreComponents.avatar/1, %{
          name: "Acme Corp",
          seed: "same-seed",
          type: :customer
        })

      project =
        render_component(&CoreComponents.avatar/1, %{
          name: "Acme Corp",
          seed: "same-seed",
          type: :project
        })

      assert customer =~ "bg-gradient-to-br from-"
      assert customer =~ "AC"
      assert customer == project
    end

    test "user avatars keep their own palette" do
      user =
        render_component(&CoreComponents.avatar/1, %{name: "Acme Corp", seed: "same-seed"})

      entity =
        render_component(&CoreComponents.avatar/1, %{
          name: "Acme Corp",
          seed: "same-seed",
          type: :customer
        })

      assert user =~ "bg-gradient-to-br from-"
      refute user == entity
    end

    test ":pending unchanged" do
      html = render_component(&CoreComponents.avatar/1, %{name: "X", seed: "s", type: :pending})
      assert html =~ "bg-warning/10 text-warning"
    end
  end
end
