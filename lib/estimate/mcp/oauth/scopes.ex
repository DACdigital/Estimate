defmodule Estimate.MCP.OAuth.Scopes do
  @moduledoc """
  The two MCP OAuth scopes. `mcp:write` implies `mcp:read`; `offline_access`
  (advertised for refresh tokens) is accepted and ignored. Stored on codes and
  tokens as a space-separated string in canonical order.
  """

  @read "mcp:read"
  @write "mcp:write"
  @ignored ["offline_access"]

  def all, do: [@read, @write]
  def read_only, do: @read
  def full, do: "#{@read} #{@write}"

  @spec parse(nil | String.t()) :: {:ok, [String.t()]} | {:error, :invalid_scope}
  def parse(nil), do: {:ok, [@read]}
  def parse(""), do: {:ok, [@read]}

  def parse(scope) when is_binary(scope) do
    requested = scope |> String.split(" ", trim: true) |> Enum.reject(&(&1 in @ignored))

    if Enum.all?(requested, &(&1 in all())) do
      {:ok, if(@write in requested, do: [@read, @write], else: [@read])}
    else
      {:error, :invalid_scope}
    end
  end

  def parse(_), do: {:error, :invalid_scope}

  # Named `join`, not `to_string`: a local `to_string/1` conflicts with the
  # auto-imported Kernel.to_string/1.
  @spec join([String.t()]) :: String.t()
  def join(scopes) when is_list(scopes), do: Enum.join(scopes, " ")

  @spec write?([String.t()] | String.t() | nil) :: boolean()
  def write?(scopes) when is_list(scopes), do: @write in scopes
  def write?(scope) when is_binary(scope), do: @write in String.split(scope, " ", trim: true)
  def write?(_), do: false
end
