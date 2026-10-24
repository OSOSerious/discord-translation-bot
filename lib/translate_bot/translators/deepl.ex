defmodule TranslateBot.Translators.DeepL do
  @moduledoc """
  DeepL backend. Free keys (ending in `:fx`) automatically use
  `api-free.deepl.com`.

  Configure with `DEEPL_API_KEY`.
  """

  @behaviour TranslateBot.Translator

  @impl true
  def available?, do: key() not in [nil, ""]

  @impl true
  def translate(text, source, target) do
    request = %{
      text: [text],
      source_lang: String.upcase(source),
      target_lang: String.upcase(target)
    }

    case Req.post(endpoint() <> "/v2/translate",
           json: request,
           headers: [{"authorization", "DeepL-Auth-Key " <> key()}]
         ) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"translations" => [%{"text" => translated} | _]}
       }} ->
        {:ok, translated}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:deepl, status, body}}

      {:error, exception} ->
        {:error, {:deepl, Exception.message(exception)}}
    end
  end

  defp key do
    System.get_env("DEEPL_API_KEY") || Application.get_env(:translate_bot, :deepl_key)
  end

  defp endpoint do
    if String.ends_with?(key() || "", ":fx"),
      do: "https://api-free.deepl.com",
      else: "https://api.deepl.com"
  end
end
