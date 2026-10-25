defmodule TranslateBot.FileTranslator do
  @moduledoc """
  Translate `.txt` attachments end-to-end and hand back an uploadable file.

  Pipeline: download attachment → chunk by lines → translate each chunk
  (auto-detected source) → reassemble → `%{filename, content, detected}`.

  Chunks keep whole lines together and stay under the backend's per-request
  character budget. Text outside the configured size limit is rejected with
  `{:error, :file_too_large}`.
  """

  require Logger

  @max_file_bytes Application.compile_env(:translate_bot, :max_translation_file_bytes, 1_000_000)
  # LibreTranslate defaults to 5,000 chars/request; stay safely under.
  @chunk_chars 2_000

  @doc """
  Translate a Discord attachment struct into `to` (or English/Spanish by
  auto-detection when `to` is `nil`).

  Returns `{:ok, %{filename: String.t(), content: String.t(), from: String.t(), to: String.t()}}`.
  """
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(attachment, opts \\ []) do
    target = Keyword.get(opts, :to)

    with {:ok, raw} <- download(attachment),
         {:ok, text} <- decode_utf8(raw),
         :ok <- check_size(text),
         {:ok, from} <- detect_language(text),
         to when is_binary(to) <- target_for(from, target),
         {:ok, translated} <- translate_chunks(text, from, to) do
      {:ok,
       %{
         filename: translated_filename(attachment, to),
         content: translated,
         from: from,
         to: to
       }}
    else
      {:error, reason} ->
        Logger.warning("file translation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # -- Public translation pipeline -------------------------------------------

  @doc """
  Translate arbitrary text (not an attachment) from `from` to `to`,
  chunk-aware. Shared by UrlTranslator and other callers.
  """
  @spec translate_text(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def translate_text(text, from, to) do
    translate_chunks(text, from, to)
  end

  # -- Steps ----------------------------------------------------------------

  defp download(%{url: url}) do
    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:download, status}}

      {:error, exception} ->
        {:error, {:download, Exception.message(exception)}}
    end
  end

  # Discord serves attachments gzip/brotli-compressed; Req auto-decompresses
  # into binaries. If we somehow get non-UTF-8 bytes, fail loudly instead of
  # silently mangling the text.
  defp decode_utf8(raw) do
    case String.valid?(raw) do
      true -> {:ok, String.replace_leading(raw, "\uFEFF", "")}
      false -> {:error, :invalid_utf8}
    end
  end

  defp check_size(text) do
    if byte_size(text) > @max_file_bytes,
      do: {:error, :file_too_large},
      else: :ok
  end

  defp detect_language(text) do
    sample = String.slice(text, 0, 2_000)

    case TranslateBot.Detect.rich(sample) do
      {:ok, code} -> {:ok, code}
      {:error, _} -> {:error, :detection_failed}
    end
  end

  # Explicit target wins; otherwise English input gets translated to Spanish
  # (keeps the bot useful for both audiences) and everything else → English.
  defp target_for(_from, to) when is_binary(to) and to != "", do: to
  defp target_for("en", _nil), do: "es"
  defp target_for(_other, _nil), do: "en"

  defp translate_chunks(text, from, to) do
    chunks = chunk_lines(text)

    results =
      Enum.reduce_while(chunks, [], fn chunk, acc ->
        case TranslateBot.Translation.translate(chunk, from, to) do
          {:ok, translated, _origin} -> {:cont, [translated | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case results do
      {:error, reason} -> {:error, reason}
      done -> {:ok, done |> Enum.reverse() |> Enum.join("\n")}
    end
  end

  # -- Chunking -------------------------------------------------------------

  @doc """
  Split text into chunks of whole lines, each under `@chunk_chars`.

  Oversized single lines are hard-split on characters. Returns `[""]` for
  blank input so callers always get a list.
  """
  @spec chunk_lines(String.t()) :: [String.t()]
  def chunk_lines(text) do
    text
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc -> add_line(acc, line) end)
    |> Enum.reverse()
    |> case do
      [] -> [""]
      chunks -> chunks
    end
  end

  defp add_line(acc, line) do
    line_len = String.length(line)

    cond do
      line_len >= @chunk_chars ->
        # Hard-split oversized lines, then continue accumulating.
        line
        |> split_hard()
        |> Enum.reverse()
        |> Enum.reduce(acc, fn piece, a -> [piece | a] end)

      acc == [] ->
        [line]

      true ->
        # `acc` is newest-first; prepend this line in front of the newest chunk.
        [current | rest] = acc
        current_len = String.length(current)

        if current_len + 1 + line_len <= @chunk_chars do
          [current <> "\n" <> line | rest]
        else
          [line, current | rest]
        end
    end
  end

  defp split_hard(line) do
    line
    |> String.codepoints()
    |> Enum.chunk_every(@chunk_chars)
    |> Enum.map(&Enum.join/1)
  end

  # -- Naming ---------------------------------------------------------------

  defp translated_filename(%{filename: filename}, to) do
    base = filename |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")
    (if base == "", do: "translation", else: base) <> "." <> to <> ".txt"
  end

  # Plain-text-ish formats we accept for translation.
  @text_extensions [".txt", ".md", ".csv", ".srt", ".html", ".htm", ".json", ".log"]

  @doc "Does this attachment look like a translatable text file?"
  @spec text_file?(map()) :: boolean()
  def text_file?(%{filename: filename, size: size}) do
    name = String.downcase(filename || "")

    name in ["", ".txt"] or String.ends_with?(name, @text_extensions) or
      (is_integer(size) and size > 0 and String.contains?(name, ".") == false)
  end
end
