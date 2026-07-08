defmodule EstimateWeb.CoreComponents.AuthInputTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EstimateWeb.CoreComponents

  defp form_field(params, key) do
    to_form(params, as: :user)[key]
  end

  test "renders a raw input with name, placeholder, and base classes" do
    html =
      render_component(&CoreComponents.auth_input/1,
        name: "code",
        value: "123",
        placeholder: "000000",
        type: "text"
      )

    assert html =~ ~s(name="code")
    assert html =~ ~s(placeholder="000000")
    assert html =~ ~s(value="123")
    assert html =~ "border-base-content/20"
    refute html =~ "border-error"
  end

  test "renders an explicit error and switches the border" do
    html =
      render_component(&CoreComponents.auth_input/1,
        name: "invite_code",
        error: "Invalid or expired invite code"
      )

    assert html =~ "Invalid or expired invite code"
    assert html =~ "border-error"
  end

  test "password type never echoes a value" do
    html =
      render_component(&CoreComponents.auth_input/1,
        type: "password",
        name: "user[password]",
        value: "supersecret"
      )

    refute html =~ "supersecret"
  end

  test "appends extra classes" do
    html =
      render_component(&CoreComponents.auth_input/1, name: "code", class: "font-mono text-center")

    assert html =~ "font-mono"
    assert html =~ "text-center"
  end

  test "field-backed input renders translated field errors" do
    field = form_field(%{"email" => "bad"}, :email)
    field = %{field | errors: [{"can't be blank", []}]}

    html = render_component(&CoreComponents.auth_input/1, field: field, type: "email")

    assert html =~ ~s(name="user[email]")
    assert html =~ "border-error"
    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "passes through functional attrs" do
    html =
      render_component(&CoreComponents.auth_input/1,
        name: "code",
        maxlength: "6",
        inputmode: "numeric",
        required: true
      )

    assert html =~ ~s(maxlength="6")
    assert html =~ ~s(inputmode="numeric")
    assert html =~ "required"
  end
end
