defmodule EstimateWeb.CoreComponents.AuthChromeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EstimateWeb.CoreComponents

  test "auth_header without subtitle uses mb-8 and no <p>" do
    html =
      render_component(&CoreComponents.auth_header/1, %{
        title: "Create your account",
        subtitle: []
      })

    assert html =~ "Create your account"
    assert html =~ "mb-8"
    refute html =~ "text-base-content/60"
  end

  test "auth_header with subtitle uses mb-2 heading + /60 subtitle" do
    html =
      render_component(&CoreComponents.auth_header/1, %{
        title: "Forgot your password?",
        subtitle: [%{inner_block: fn _, _ -> "We'll send a reset link" end}]
      })

    assert html =~ "Forgot your password?"
    assert html =~ "mb-2"
    assert html =~ "text-center text-base-content/60 mb-8"
    assert html =~ "We&#39;ll send a reset link" or html =~ "We'll send a reset link"
  end

  test "auth_submit with loading sets phx-disable-with" do
    html =
      render_component(&CoreComponents.auth_submit/1, %{
        loading: "Creating account...",
        inner_block: [%{inner_block: fn _, _ -> "Create Account" end}]
      })

    assert html =~ ~s(phx-disable-with="Creating account...")
    assert html =~ "Create Account"
    assert html =~ "bg-neutral"
  end

  test "auth_submit without loading omits phx-disable-with" do
    html =
      render_component(&CoreComponents.auth_submit/1, %{
        inner_block: [%{inner_block: fn _, _ -> "Continue with Email" end}]
      })

    refute html =~ "phx-disable-with"
    assert html =~ "Continue with Email"
  end

  test "oauth_section renders divider + google button" do
    html = render_component(&CoreComponents.oauth_section/1, %{href: "/auth/google"})
    assert html =~ "/auth/google"
  end
end
