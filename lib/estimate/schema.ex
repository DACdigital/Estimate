defmodule Estimate.Schema do
  @moduledoc """
  Custom schema with UUID defaults for primary keys and foreign keys.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
