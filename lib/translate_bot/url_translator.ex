defmodule TranslateBot.UrlTranslator do
  @moduledoc """
  Fetch a web page, extract readable text, translate it, return a `.txt`.

  Uses `TranslateBot.FileTranslator.translate_text/3` for the actual
  translation pipeline so chunking + caching behave identically.
  """

  require Logger

  @max_page_bytes 2_000_000

  @doc """
  Translate the readable text of `url`.

  Returns `{:ok, %{title: String.t(), content: String.t(), from: String.t(), to: String.t()}}`.
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(url, opts \\ []) do
    with {:ok, html} <- fetch(url),
         {:ok, %{title: title, text: text}} <- extract(html),
         :ok <- check_size(text),
         {:ok, from} <- detect_language(text),
         to when is_binary(to) <- target_for(from, opts),
         {:ok, translated} <- translate(text, from, to) do
      {:ok, %{title: title || "page", content: translated, from: from, to: to}}
    else
      {:error, reason} ->
        Logger.warning("url translation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch(url) do
    case Req.get(url, redirect: true, connect_options: [timeout: 10_000],
           receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, headers: headers, body: body}}
      when is_binary(body) ->
        if content_type_html?(headers), do: {:ok, body}, else: {:error, :not_html}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, {:fetch, Exception.message(exception)}}
    end
  end

  defp content_type_html?(headers) do
    case Req.Response.get_header(headers, "content-type") do
      [ct | _] -> String.contains?(ct, "text/html")
      [] -> true
    end
  end

  # Extremely lightweight readability pass: drop script/style/head, tags,
  # then collapse whitespace. No dependency, good enough for articles.
  defp extract(html) do
    title =
      case Regex.run(~r/<title[^>]*>(.*?)<\/title>/is, html) do
        [_, t | _] -> t |> String.trim() |> decode_entities()
        _ -> nil
      end

    text =
      html
      |> String.replace(~r/<(script|style|head|nav|footer|noscript)[^>]*>.*?<\/\1>/is, " ")
      |> String.replace(~r/<br\s*\/?>/i, "\n")
      |> String.replace(~r/<\/(p|div|h[1-6]|li|tr)>/i, "\n")
      |> String.replace(~r/<[^>]+>/, " ")
      |> decode_entities()
      |> String.replace(~r/[ \t]+/, " ")
      |> String.replace(~r/\n{3,}/, "\n\n")
      |> String.trim()

    if String.length(text) < 40 do
      {:error, :no_readable_text}
    else
      {:ok, %{title: title, text: text}}
    end
  end

  # Avoid a dependency: decode the handful of entities that matter.
  @entities %{
    "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"",
    "&#39;" => "'", "&apos;" => "'", "&nbsp;" => " ", "&mdash;" => "—",
    "&ndash;" => "–", "&hellip;" => "…", "&laquo;" => "«", "&raquo;" => "»"
  }

  defp decode_entities(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end

  defp check_size(text) do
    if byte_size(text) > @max_page_bytes, do: {:error, :file_too_large}, else: :ok
  end

  defp detect_language(text) do
    case TranslateBot.Detect.rich(String.slice(text, 0, 2_000)) do
      {:ok, code} -> {:ok, code}
      {:error, _} -> {:error, :detection_failed}
    end
  end

  defp target_for("en", _opts), do: "es"

  defp target_for(_other, opts) do
    case Keyword.get(opts, :to) do
      nil -> "en"
      "" -> "en"
      lang -> lang
    end
  end

  defp translate(text, from, to) do
    TranslateBot.FileTranslator.translate_text(text, from, to)
  end
end
