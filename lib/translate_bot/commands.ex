defmodule TranslateBot.Commands do
  @moduledoc """
  Slash-command definitions and (idempotent) registration.

  Commands:
    * `/translate text:<msg>`            — auto-detect ES↔EN and translate
    * `/translate-to lang: text:`        — translate into a specific language
    * `/translate-file file: lang:`      — translate a text file attachment
    * `/translate-url url: lang:`        — translate a web page
    * `/detect text:<msg>`               — report the detected language
    * `/auto`                            — toggle auto-translate in this channel
    * `/stats`                           — translation usage stats
  """

  alias Nostrum.Api.ApplicationCommand

  require Logger

  # The languages offered in dropdowns. LibreTranslate supports 50; these
  # are the most useful + the ones Discord users will actually pick.
  @language_choices [
    %{name: "Spanish", value: "es"},
    %{name: "English", value: "en"},
    %{name: "Chinese (Simplified)", value: "zh-Hans"},
    %{name: "Chinese (Traditional)", value: "zh-Hant"},
    %{name: "French", value: "fr"},
    %{name: "German", value: "de"},
    %{name: "Italian", value: "it"},
    %{name: "Portuguese", value: "pt"},
    %{name: "Japanese", value: "ja"},
    %{name: "Korean", value: "ko"},
    %{name: "Russian", value: "ru"},
    %{name: "Arabic", value: "ar"},
    %{name: "Hindi", value: "hi"},
    %{name: "Dutch", value: "nl"},
    %{name: "Polish", value: "pl"},
    %{name: "Turkish", value: "tr"},
    %{name: "Ukrainian", value: "uk"},
    %{name: "Vietnamese", value: "vi"},
    %{name: "Thai", value: "th"},
    %{name: "Greek", value: "el"},
    %{name: "Hebrew", value: "he"},
    %{name: "Swedish", value: "sv"},
    %{name: "Danish", value: "da"},
    %{name: "Finnish", value: "fi"},
    %{name: "Norwegian", value: "nb"},
    %{name: "Czech", value: "cs"},
    %{name: "Romanian", value: "ro"},
    %{name: "Hungarian", value: "hu"},
    %{name: "Indonesian", value: "id"},
    %{name: "Persian", value: "fa"}
  ]

  # Discord caps choices at 25 per option.
  @translate_to_choices Enum.take(@language_choices, 25)

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
        },
        %{
          name: "hidden",
          description: "Reply only to you (ephemeral)",
          type: 5,
          required: false
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
          choices: @translate_to_choices
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
      name: "translate-file",
      description: "Translate a text file (auto-detects the language)",
      options: [
        %{
          name: "file",
          description: "The .txt/.md/.csv/.srt/.html file to translate",
          type: 11,
          required: true
        },
        %{
          name: "lang",
          description: "Target language (default: English)",
          type: 3,
          required: false,
          choices: @translate_to_choices
        }
      ]
    },
    %{
      name: "translate-url",
      description: "Translate a web page (auto-detects the language)",
      options: [
        %{
          name: "url",
          description: "The page URL to translate",
          type: 3,
          required: true
        },
        %{
          name: "lang",
          description: "Target language (default: English)",
          type: 3,
          required: false,
          choices: @translate_to_choices
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
    },
    %{
      name: "stats",
      description: "Translation usage stats for this bot"
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

  @doc "The shared language choices (for /translate-to and /translate-file)."
  def language_choices, do: @language_choices
end
