defmodule TranslateBot.Detect do
  @moduledoc """
  Lightweight ES/EN language detection.

  Pure heuristics — no network call:
    1. Spanish-specific characters (á é í ó ú ñ ü ¿ ¡) decide immediately.
    2. Otherwise, the majority of stop words (el/la/que vs the/of/is) wins.
    3. Default to English on a tie or no signal.
  """

  @spanish_chars ~r/[áéíóúñü¿¡]/u

  @spanish_words MapSet.new(~w(
    hola el la los las lo un una unos unas de del al que y en es está están
    era por para con se su sus le les ya pero como muy cuando donde aquí
    sí porque quién qué más
  ))

  @english_words MapSet.new(~w(
    the a an of to in and is are was were be been being it its this that
    these those for on with as at by from or but not have has had do does
    did you your we they he she his her i my our their will would can
    could should about into over under
  ))

  @spec detect(String.t()) :: String.t()
  def detect(text) when is_binary(text) do
    cond do
      Regex.match?(@spanish_chars, text) -> "es"
      true -> stop_word_majority(text)
    end
  end

  @doc """
  Detect *any* language, falling back to LibreTranslate's `/detect`.

  1. Try the fast local ES/EN heuristics — but only trust them when the
     text is written in Latin script (Chinese/Japanese/etc. would otherwise
     be misclassified as English).
  2. Non-Latin scripts or ambiguous cases go to the backend detector,
     which returns codes like `zh-Hans`, `ja`, `ru`.

  Returns `{:ok, code}` or `{:error, reason}`.
  """
  @spec rich(String.t()) :: {:ok, String.t()} | {:error, term()}
  def rich(text) when is_binary(text) do
    cond do
      latin_script?(text) ->
        {:ok, detect(text)}

      true ->
        TranslateBot.Translators.LibreTranslate.detect(text)
    end
  end

  @latin ~r/^[\p{Latin}\p{Common}\s]*$/u

  defp latin_script?(text) do
    # At least one letter and no non-Latin script characters.
    String.match?(text, ~r/\p{L}/u) and Regex.match?(@latin, text)
  end

  @doc "The opposite language: `other(\"es\")` → `\"en\"` and vice versa."
  @spec other(String.t()) :: String.t()
  def other("es"), do: "en"
  def other("en"), do: "es"
  def other(_), do: "es"

  defp stop_word_majority(text) do
    words = String.split(String.downcase(text), ~r/[^\p{L}']+/u, trim: true)

    es = stop_word_count(words, @spanish_words)
    en = stop_word_count(words, @english_words)

    if es > en, do: "es", else: "en"
  end

  defp stop_word_count(words, set), do: Enum.count(words, &MapSet.member?(set, &1))
end
