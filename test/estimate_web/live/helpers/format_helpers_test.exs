defmodule EstimateWeb.FormatHelpersTest do
  use ExUnit.Case, async: true

  import EstimateWeb.FormatHelpers

  doctest EstimateWeb.FormatHelpers

  describe "domain/1" do
    test "strips scheme" do
      assert domain("https://acme.com") == "acme.com"
      assert domain("http://acme.com") == "acme.com"
    end

    test "strips leading www." do
      assert domain("https://www.acme.com") == "acme.com"
    end

    test "keeps non-www subdomains" do
      assert domain("https://app.acme.co.uk") == "app.acme.co.uk"
    end

    test "drops path, query, trailing slash" do
      assert domain("https://acme.com/about?ref=1") == "acme.com"
      assert domain("https://acme.com/") == "acme.com"
    end

    test "nil, empty, and host-less input → nil" do
      assert domain(nil) == nil
      assert domain("") == nil
      assert domain("not a url") == nil
    end
  end
end
