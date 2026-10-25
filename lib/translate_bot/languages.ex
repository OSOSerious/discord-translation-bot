defmodule TranslateBot.Languages do
  @moduledoc """
  Language metadata: flag emoji ↔ ISO-ish code, display names.

  Used by reaction-translate (react with any flag → translate into that
  language) and by `/stats` output formatting. Codes follow LibreTranslate
  naming (`zh-Hans`, `pt-BR`, …).
  """

  @flags %{
    "🇬🇧" => "en", "🇺🇸" => "en", "🇪🇸" => "es", "🇨🇳" => "zh-Hans",
    "🇹🇼" => "zh-Hant", "🇭🇰" => "zh-Hant", "🇫🇷" => "fr", "🇩🇪" => "de",
    "🇮🇹" => "it", "🇵🇹" => "pt", "🇧🇷" => "pt", "🇯🇵" => "ja", "🇰🇷" => "ko",
    "🇷🇺" => "ru", "🇸🇦" => "ar", "🇮🇳" => "hi", "🇳🇱" => "nl", "🇵🇱" => "pl",
    "🇺🇦" => "uk", "🇻🇳" => "vi", "🇹🇭" => "th", "🇬🇷" => "el",
    "🇮🇱" => "he", "🇸🇪" => "sv", "🇩🇰" => "da", "🇫🇮" => "fi", "🇳🇴" => "nb",
    "🇨🇿" => "cs", "🇷🇴" => "ro", "🇭🇺" => "hu", "🇮🇩" => "id", "🇮🇷" => "fa",
    "🇦🇱" => "sq", "🇦🇿" => "az", "🇧🇬" => "bg", "🇧🇩" => "bn", "🇪🇪" => "et",
    "🇮🇪" => "ga", "🇰🇬" => "ky", "🇱🇻" => "lv", "🇱🇹" => "lt", "🇲🇾" => "ms",
    "🇵🇭" => "tl", "🇸🇰" => "sk", "🇸🇮" => "sl", "🇿🇦" => "sw"
  }

  @names %{
    "en" => "English", "es" => "Spanish", "zh-Hans" => "Chinese (Simplified)",
    "zh-Hant" => "Chinese (Traditional)", "fr" => "French", "de" => "German",
    "it" => "Italian", "pt" => "Portuguese", "ja" => "Japanese",
    "ko" => "Korean", "ru" => "Russian", "ar" => "Arabic", "hi" => "Hindi",
    "nl" => "Dutch", "pl" => "Polish", "tr" => "Turkish", "uk" => "Ukrainian",
    "vi" => "Vietnamese", "th" => "Thai", "el" => "Greek", "he" => "Hebrew",
    "sv" => "Swedish", "da" => "Danish", "fi" => "Finnish", "nb" => "Norwegian",
    "cs" => "Czech", "ro" => "Romanian", "hu" => "Hungarian",
    "id" => "Indonesian", "fa" => "Persian"
  }

  @reverse_flags @flags |> Map.new(fn {f, c} -> {c, f} end)

  @doc "Language code for a flag emoji, or `nil` if unknown."
  @spec from_flag(String.t()) :: String.t() | nil
  def from_flag(flag), do: Map.get(@flags, flag)

  @doc "Flag emoji for a language code, or 🌐 when unknown."
  @spec flag(String.t()) :: String.t()
  def flag("en"), do: "🇬🇧"
  def flag(code), do: Map.get(@reverse_flags, code, "🌐")

  @doc "Human-readable name, or the code itself when unknown."
  @spec name(String.t()) :: String.t()
  def name(code), do: Map.get(@names, code, code)

  @doc "All supported flag → code pairs (for tests / introspection)."
  @spec flags() :: map()
  def flags, do: @flags
end
