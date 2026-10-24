defmodule TranslateBot.TestSupport.FailingBackend do
  @moduledoc "Always errors — used to exercise the fallback chain."
  @behaviour TranslateBot.Translator

  @impl true
  def available?, do: true

  @impl true
  def translate(_text, _source, _target), do: {:error, :always_fails}
end

defmodule TranslateBot.TestSupport.UpperBackend do
  @moduledoc "Returns the uppercased input — a deterministic fake translator."
  @behaviour TranslateBot.Translator

  @impl true
  def available?, do: true

  @impl true
  def translate(text, _source, _target), do: {:ok, String.upcase(text)}
end
