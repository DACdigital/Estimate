defmodule Estimate.TemplatesFixturesTest do
  use Estimate.DataCase, async: true

  import Estimate.TemplatesFixtures

  test "template_fixture/2 creates a persisted estimation template" do
    template = template_fixture()
    assert template.id
    assert template.name =~ "Test Template"
  end
end
