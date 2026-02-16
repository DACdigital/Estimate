defmodule Estimate.AI.OpenRouter do
  @url "https://openrouter.ai/api/v1/chat/completions"
  @timeout 30_000

  @default_system_prompt """
  You are a software estimation assistant. Enhance this description: make it clearer, \
  more structured, better for estimation. Return ONLY the improved description, no markdown.\
  """

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
