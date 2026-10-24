defmodule TranslateBot.Commands do
  @moduledoc """
  Slash-command definitions and (idempotent) registration.

  Commands:
    * `/translate text:<msg>`   — auto-detect ES↔EN and translate
    * `/detect text:<msg>`      — report the detected language
    * `/auto`                   — toggle auto-translate in this channel
  """

  alias Nostrum.Api.ApplicationCommand

  require Logger

  @commands [
    %{
      name: "translate",
      description: "Translate a message between English and Spanish",
      options: [
        %{
          name: "text",
          description: "The message to translate",
          type: 3,
          required: true
        }
      ]
    },
    %{
      name: "translate-to",
      description: "Translate a message into a specific language",
      options: [
        %{
          name: "lang",
          description: "Target language",
          type: 3,
          required: true,
          choices: [
            %{name: "Spanish", value: "es"},
            %{name: "English", value: "en"}
          ]
        },
        %{
          name: "text",
          description: "The message to translate",
          type: 3,
          required: true
        }
      ]
    },
    %{
      name: "detect",
      description: "Detect whether a message is English or Spanish",
      options: [
        %{
          name: "text",
          description: "The message to inspect",
          type: 3,
          required: true
        }
      ]
    },
    %{
      name: "auto",
      description: "Toggle automatic translation in this channel"
    }
  ]

  @doc "Register (or update) all commands globally. Safe to call on every boot."
  def register do
    Enum.each(@commands, fn command ->
      case ApplicationCommand.create_global_command(command) do
        {:ok, _} ->
          Logger.info("registered /#{command.name}")
          :ok

        error ->
          Logger.warning("command registration failed for #{command.name}: #{inspect(error)}")
      end
    end)
  end

  @doc "The list of command definitions (useful in tests)."
  def all, do: @commands
end
