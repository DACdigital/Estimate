defmodule EstimateWeb.FormatHelpers do
  @moduledoc """
  Pure formatting helpers for HEEx templates.
  """

  @doc """
  Bare display domain of a URL: host without scheme, leading "www.", or path.

      iex> EstimateWeb.FormatHelpers.domain("https://www.acme.com/about")
      "acme.com"

      iex> EstimateWeb.FormatHelpers.domain(nil)
      nil
  """
  def domain(nil), do: nil

  def domain(url) when is_binary(url) do
    case URI.parse(url).host do
      nil -> nil
      "" -> nil
      host -> String.replace_prefix(host, "www.", "")
    end
  end
end
