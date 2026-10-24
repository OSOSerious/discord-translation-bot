defmodule TranslateBot.Translation do
  @moduledoc """
  Translation orchestrator: cache lookup → backend fallback chain → cache store.

  Backends are configured under `config :translate_bot, :backends` and tried
  in order; the first `{:ok, _}` wins. Unavailable backends (e.g. DeepL
  without an API key) are skipped.
  """

  alias TranslateBot.Cache

  @doc """
  Translate `text` from `source` to `target`.

  Returns `{:ok, translated, :fresh | :cached}` or `{:error, reason}`.
  """
  @spec translate(String.t(), String.t(), String.t()) ::
          {:ok, String.t(), :fresh | :cached} | {:error, term()}
  def translate(text, source, target) when source != target do
    case Cache.fetch(text, source, target) do
      {:ok, translated} ->
        {:ok, translated, :cached}

      :miss ->
        case try_backends(backends(), text, source, target, []) do
          {:ok, translated} ->
            Cache.put(text, source, target, translated)
            {:ok, translated, :fresh}

          {:error, _} = error ->
            error
        end
    end
  end

  def translate(_text, same, same), do: {:error, :same_language}

  @doc """
  Auto-detect the language of `text` and translate it to the other one.

  Returns `{:ok, %{from: lang, to: lang, text: translated, origin: origin}}`.
  """
  @spec auto(String.t()) :: {:ok, map()} | {:error, term()}
  def auto(text) do
    case String.trim(text) do
      "" ->
        {:error, :empty_text}

      trimmed ->
        from = TranslateBot.Detect.detect(trimmed)
        to = TranslateBot.Detect.other(from)

        case translate(trimmed, from, to) do
          {:ok, translated, origin} ->
            {:ok, %{from: from, to: to, text: translated, origin: origin}}

          {:error, _} = error ->
            error
        end
    end
  end

  # -- Internals ------------------------------------------------------------

  defp backends, do: Application.get_env(:translate_bot, :backends, [])

  defp try_backends([], _text, _source, _target, errors),
    do: {:error, {:all_backends_failed, Enum.reverse(errors)}}

  defp try_backends([backend | rest], text, source, target, errors) do
    if backend_available?(backend) do
      case backend.translate(text, source, target) do
        {:ok, translated} ->
          {:ok, translated}

        {:error, reason} ->
          try_backends(rest, text, source, target, [{backend, reason} | errors])
      end
    else
      try_backends(rest, text, source, target, errors)
    end
  end

  defp backend_available?(backend) do
    Code.ensure_loaded?(backend) and
      function_exported?(backend, :available?, 0) and
      backend.available?()
  end
end
