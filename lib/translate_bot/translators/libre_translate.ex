defmodule TranslateBot.Translators.LibreTranslate do
  @moduledoc """
  LibreTranslate backend (self-hosted or public instance).

  Configure with:
    * `LIBRETRANSLATE_URL`     - base URL (default `http://localhost:5000`)
    * `LIBRETRANSLATE_API_KEY` - optional, required by public instances
  """

  @behaviour TranslateBot.Translator

  @impl true
  def available?, do: base_url() != ""

  @doc """
  Detect the language of `text` via LibreTranslate's `/detect` endpoint.

  Returns `{:ok, code}` (e.g. `"zh-Hans"`, `"en"`) or `{:error, reason}`.
  Note: `translate/3` accepts `source: "auto"` as well, so detection is
  only needed to pick a *target* language.
  """
  @spec detect(String.t()) :: {:ok, String.t()} | {:error, term()}
  def detect(text) do
    body =
      %{q: text}
      |> maybe_put(:api_key, api_key())

    case Req.post(base_url() <> "/detect", json: body) do
      {:ok, %Req.Response{status: 200, body: [%{"language" => code} | _]}} ->
        {:ok, code}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:libre_detect, status, body}}

      {:error, exception} ->
        {:error, {:libre_detect, Exception.message(exception)}}
    end
  end

  @impl true
  def translate(text, source, target) do
    body =
      %{q: text, source: source, target: target, format: "text"}
      |> maybe_put(:api_key, api_key())

    case Req.post(base_url() <> "/translate", json: body) do
      {:ok, %Req.Response{status: 200, body: %{"translatedText" => translated}}} ->
        {:ok, translated}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:libre_translate, status, body}}

      {:error, exception} ->
        {:error, {:libre_translate, Exception.message(exception)}}
    end
  end

  defp base_url do
    "LIBRETRANSLATE_URL"
    |> System.get_env(
      Application.get_env(:translate_bot, :libre_translate_url, "http://localhost:5000")
    )
    |> to_string()
    |> String.trim_trailing("/")
  end

  defp api_key do
    System.get_env("LIBRETRANSLATE_API_KEY") ||
      Application.get_env(:translate_bot, :libre_translate_key)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
