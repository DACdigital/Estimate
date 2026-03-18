defmodule EstimateWeb.FormClasses do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      @label_class "block text-xs font-medium text-base-content/60 mb-1.5"
      @input_class "w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
    end
  end
end
