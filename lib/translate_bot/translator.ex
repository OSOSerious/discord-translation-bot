defmodule TranslateBot.Translator do
  @moduledoc """
  Behaviour for translation backends.

  Implementations must provide `translate/3` returning
  `{:ok, translated_text}` or `{:error, reason}`, plus `available?/0`
  so the fallback chain can skip backends without credentials.
  """

  @callback translate(text :: String.t(), source :: String.t(), target :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback available?() :: boolean()
end
