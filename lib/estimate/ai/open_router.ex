defmodule Estimate.AI.OpenRouter do
  @url "https://openrouter.ai/api/v1/chat/completions"
  @models_url "https://openrouter.ai/api/v1/models"
  @key_url "https://openrouter.ai/api/v1/key"
  @timeout 30_000
  @cache_ttl :timer.hours(1)

  @default_system_prompt """
  You are a software estimation assistant. Enhance this description: make it clearer, \
  more structured, better for estimation. Return ONLY the improved description, no markdown.\
  """

  # --- Model listing & search ---

  def list_models do
    case get_cached_models() do
      {:ok, models} -> {:ok, models}
      :miss -> fetch_and_cache_models()
    end
  end

  def search_models(query) do
    case list_models() do
      {:ok, models} ->
        q = String.downcase(query)

        filtered =
          Enum.filter(models, fn m ->
            String.contains?(String.downcase(m.id), q) or
              String.contains?(String.downcase(m.name || ""), q)
          end)

        {:ok, Enum.take(filtered, 20)}

      error ->
        error
    end
  end

  defp get_cached_models do
    case :ets.lookup(:openrouter_models, :models) do
      [{:models, models, expires_at}]
      when expires_at > 0 ->
        if expires_at > System.monotonic_time(:millisecond) do
          {:ok, models}
        else
          :miss
        end

      _ ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp fetch_and_cache_models do
    case Req.get(@models_url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        models =
          data
          |> Enum.map(fn m ->
            %{
              id: m["id"],
              name: m["name"],
              context_length: m["context_length"],
              pricing_prompt: get_in(m, ["pricing", "prompt"]),
              pricing_completion: get_in(m, ["pricing", "completion"])
            }
          end)
          |> Enum.sort_by(& &1.name)

        ensure_ets_table()
        expires = System.monotonic_time(:millisecond) + @cache_ttl
        :ets.insert(:openrouter_models, {:models, models, expires})
        {:ok, models}

      {:ok, %{status: s, body: b}} ->
        {:error, "OpenRouter #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp ensure_ets_table do
    case :ets.info(:openrouter_models) do
      :undefined -> :ets.new(:openrouter_models, [:set, :public, :named_table])
      _ -> :ok
    end
  end

  # --- Key info / balance ---

  def get_key_info(api_key) do
    case Req.get(@key_url,
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok,
         %{
           usage: data["usage"],
           limit: data["limit"],
           limit_remaining: data["limit_remaining"],
           is_free_tier: data["is_free_tier"]
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenRouter #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # --- Chat completions ---

  def enhance_description(api_key, model, system_prompt, name, description) do
    system = system_prompt || @default_system_prompt
    user_msg = "Item: #{name}\n\nDescription:\n#{description}"

    body = %{
      model: model,
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user_msg}
      ]
    }

    case Req.post(@url,
           json: body,
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: @timeout
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => text}} | _]}}} ->
        {:ok, String.trim(text)}

      {:ok, %{status: status, body: body}} ->
        {:error, "OpenRouter returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end
end
