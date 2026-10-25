defmodule TranslateBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :translate_bot,
      version: "0.3.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TranslateBot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nostrum, "~> 0.8"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      # Nostrum tries to connect to the Discord gateway when the app starts.
      # Tests don't need a live connection, so we compile without starting.
      test: "test --no-start"
    ]
  end
end
