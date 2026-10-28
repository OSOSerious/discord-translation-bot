defmodule TranslateBot.Consumer do
  @moduledoc """
  Discord gateway event consumer.

  Handles:
    * `INTERACTION_CREATE`     — `/translate`, `/translate-to`, `/detect`, `/auto`
    * `MESSAGE_CREATE`         — per-channel auto-translate (see `TranslateBot.Channels`)
    * `MESSAGE_REACTION_ADD`   — react 🇬🇧/🇪🇸 to translate that message
  """

  require Logger

  use Nostrum.Consumer

  alias Nostrum.Api.Interaction, as: InteractionApi
  alias Nostrum.Api.Message, as: MessageApi
  alias Nostrum.Struct.Event.MessageReactionAdd
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.Message

  # How long a (message_id, target_lang) reaction pair stays "recent" —
  # prevents the same user (or spam-reactors) re-triggering translations.
  @reaction_dedupe_ms :timer.seconds(30)

  def handle_event({:READY, _ready, _ws_state}) do
    # Register slash commands once the gateway session is up.
    if Application.get_env(:translate_bot, :register_commands, true) do
      TranslateBot.Commands.register()
    end

    :ignore
  end

  def handle_event({:INTERACTION_CREATE, %Interaction{} = interaction, _ws_state}) do
    handle_interaction(interaction)
    :ignore
  end

  def handle_event({:MESSAGE_CREATE, %Message{} = msg, _ws_state}) do
    handle_message(msg)
    :ignore
  end

  def handle_event({:MESSAGE_REACTION_ADD, %MessageReactionAdd{} = reaction, _ws_state}) do
    handle_reaction(reaction)
    :ignore
  end

  # Unhandled events fall through to the catch-all `use Nostrum.Consumer` injects.

  # -- Interactions ---------------------------------------------------------

  defp handle_interaction(%Interaction{data: %{name: "translate"}} = interaction) do
    text = option(interaction, "text")
    ephemeral? = ephemeral?(interaction)

    case TranslateBot.Translation.auto(text, interaction.channel_id) do
      {:ok, %{from: from, to: to, text: translated}} ->
        respond(interaction, "**#{flag(from)} → #{flag(to)}:** #{translated}", ephemeral?)

      {:error, :empty_text} ->
        respond(interaction, "Give me something to translate! `/translate text: hola`", ephemeral?)

      {:error, reason} ->
        Logger.error("translate failed: #{inspect(reason)}")
        respond(interaction, "Translation failed — try again in a moment.", ephemeral?)
    end
  end

  defp handle_interaction(%Interaction{data: %{name: "detect"}} = interaction) do
    text = option(interaction, "text")

    case String.trim(text) do
      "" ->
        respond(interaction, "Give me some text! `/detect text: hola`")

      trimmed ->
        lang = TranslateBot.Detect.detect(trimmed)
        respond(interaction, "That looks like **#{language_name(lang)}** #{flag(lang)}")
    end
  end

  defp handle_interaction(%Interaction{data: %{name: "translate-to"}} = interaction) do
    target = option(interaction, "lang") |> normalize_lang()
    text = option(interaction, "text")
    source = TranslateBot.Detect.detect(text)
    source = if source == target, do: TranslateBot.Detect.other(target), else: source

    case TranslateBot.Translation.translate(text, source, target) do
      {:ok, translated, _origin} ->
        respond(interaction, "**#{flag(source)} → #{flag(target)}:** #{translated}")

      {:error, :empty_text} ->
        respond(interaction, "Give me something to translate!")

      {:error, reason} ->
        Logger.error("translate-to failed: #{inspect(reason)}")
        respond(interaction, "Translation failed — try again in a moment.")
    end
  end

  defp handle_interaction(%Interaction{data: %{name: "translate-file"}} = interaction) do
    # Ack immediately (translation takes a while), then edit in the result.
    InteractionApi.create_response(interaction, %{type: 5, data: %{content: "Translating… 🌐"}})

    attachment =
      interaction.data.resolved
      |> Map.get(:attachments, %{})
      |> Map.values()
      |> List.first()

    to = option(interaction, "lang")

    if attachment do
      Task.start(fn ->
        case TranslateBot.FileTranslator.run(attachment, to: to) do
          {:ok, %{filename: filename, content: content, from: from, to: to_lang}} ->
            upload_file_followup(interaction, filename, content, from, to_lang)

          {:error, :file_too_large} ->
            followup(interaction, "That file is too big to translate (1 MB max).")

          {:error, :invalid_utf8} ->
            followup(interaction, "That doesn't look like a UTF-8 text file — save it as UTF-8 and retry.")

          {:error, reason} ->
            Logger.warning("translate-file failed: #{inspect(reason)}")
            followup(interaction, "Couldn't translate that file — try again in a moment.")
        end
      end)
    else
      followup(interaction, "Upload a text file with the command.")
    end

    :ok
  end

  defp handle_interaction(%Interaction{data: %{name: "translate-url"}} = interaction) do
    url = String.trim(option(interaction, "url"))
    to = option(interaction, "lang")

    unless url =~ ~r/^https?:\/\// do
      respond(interaction, "That doesn't look like a valid URL (needs http:// or https://).")
    else
      # Ack now; the fetch + translation happens in the background.
      InteractionApi.create_response(interaction, %{type: 5, data: %{content: "Fetching page… 🌐"}})

      Task.start(fn ->
        case TranslateBot.UrlTranslator.run(url, to: to) do
          {:ok, %{title: title, content: content, from: from, to: to_lang}} ->
            upload_file_followup(
              interaction,
              "#{slug(title)}.#{to_lang}.txt",
              content,
              from,
              to_lang
            )

          {:error, :not_html} ->
            followup(interaction, "That URL doesn't point to an HTML page.")

          {:error, reason} ->
            Logger.warning("translate-url failed: #{inspect(reason)}")
            followup(interaction, "Couldn't fetch or translate that page — check the URL.")
        end
      end)
    end

    :ok
  end

  defp handle_interaction(%Interaction{data: %{name: "stats"}} = interaction) do
    stats = TranslateBot.Stats.snapshot()
    channels_on = TranslateBot.Channels.count()

    top_langs =
      stats.langs
      |> Enum.sort_by(fn {_k, v} -> -v end)
      |> Enum.take(3)
      |> Enum.map(fn {{s, t}, n} -> "#{flag(s)}→#{flag(t)} **#{n}**" end)
      |> Enum.join(" · ")

    message =
      [
        "📊 **TranslateBot stats**",
        "Translations: **#{stats.total}** (cache hits: #{stats.cache_hits})",
        "Auto-translate channels: **#{channels_on}**",
        if(top_langs != "", do: "Top pairs: #{top_langs}", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    respond(interaction, message)
  end

  defp handle_interaction(%Interaction{data: %{name: "auto"}} = interaction) do
    channel_id = interaction.channel_id
    enabled = TranslateBot.Channels.toggle(channel_id)

    if enabled do
      respond(interaction, "Auto-translate **enabled** 🌐 — I'll translate every message ES↔EN here.")
    else
      respond(interaction, "Auto-translate **disabled** — staying quiet now.")
    end
  end

  defp handle_interaction(_other), do: :ignore

  # -- Reaction-translate ---------------------------------------------------

  defp handle_reaction(%MessageReactionAdd{emoji: %{name: emoji_name}} = reaction) do
    case TranslateBot.Languages.from_flag(emoji_name) do
      nil ->
        :ignore

      target ->
        if fresh_reaction?(reaction.message_id, target) do
          case MessageApi.get(reaction.channel_id, reaction.message_id) do
            {:ok, %Message{content: content}} ->
              translate_reacted(content, target, reaction)

            error ->
              Logger.warning("reaction fetch failed: #{inspect(error)}")
          end
        end

        :ignore
    end
  end

  defp handle_reaction(_other), do: :ignore

  defp translate_reacted(content, target, reaction) do
    case String.trim(content || "") do
      "" ->
        :ignore

      trimmed ->
        case TranslateBot.Detect.rich(trimmed) do
          {:ok, source} when source == target ->
            # Already in the requested language — nothing to do.
            :ignore

          {:ok, source} ->
            case TranslateBot.Translation.translate(trimmed, source, target, reaction.channel_id) do
              {:ok, translated, _origin} ->
                respond_message(
                  %Message{channel_id: reaction.channel_id, author: %{bot: false}},
                  "**#{flag(source)} → #{flag(target)}:** #{translated}"
                )

              {:error, reason} ->
                Logger.warning("reaction translate failed: #{inspect(reason)}")
            end

          {:error, _reason} ->
            :ignore
        end
    end
  end

  # Cheap in-memory dedupe: a small ETS-free table inside the consumer
  # process dictionary. Good enough for a single-node bot.
  defp fresh_reaction?(message_id, target) do
    key = {:rxn, message_id, target}
    now = System.system_time(:millisecond)

    case Process.get(key) do
      ts when is_integer(ts) and now - ts < @reaction_dedupe_ms ->
        false

      _ ->
        Process.put(key, now)
        true
    end
  end

  # -- Auto-translate -------------------------------------------------------

  defp handle_message(%Message{author: %{bot: true}}), do: :ignore

  defp handle_message(%Message{attachments: [attachment | _]} = msg) do
    # Text attachments in an /auto channel get translated and posted back.
    if TranslateBot.Channels.enabled?(msg.channel_id) and
         TranslateBot.FileTranslator.text_file?(attachment) do
      Task.start(fn ->
        case TranslateBot.FileTranslator.run(attachment) do
          {:ok, %{filename: filename, content: content, from: from, to: to}} ->
            upload(msg, filename, content, from, to)

          {:error, :file_too_large} ->
            respond_message(msg, "That file is too big to translate (1 MB max).")

          {:error, :invalid_utf8} ->
            respond_message(msg, "That doesn't look like a UTF-8 text file.")

          {:error, _} ->
            respond_message(msg, "Couldn't translate that file — try again in a moment.")
        end
      end)
    end

    :ignore
  end

  defp handle_message(%Message{} = msg) do
    if TranslateBot.Channels.enabled?(msg.channel_id) and translatable?(msg.content) do
      case TranslateBot.Translation.auto(msg.content) do
        {:ok, %{text: translated}} ->
          respond_message(msg, translated)

        _ ->
          :ignore
      end
    end

    :ignore
  end

  defp upload(%Message{} = msg, filename, content, from, to) do
    case MessageApi.create(msg.channel_id,
           content: "📄 Translated #{flag(from)} → #{flag(to)} — here's your file:",
           files: [%{name: filename, body: content}]
         ) do
      {:ok, _} -> :ok
      error -> Logger.warning("file upload failed: #{inspect(error)}")
    end
  end

  # Smart skip: don't waste API calls (or spam the channel) on messages
  # that nobody wants translated.
  @url_regex ~r/https?:\/\/\S+/
  @mention_regex ~r/<@[!&]?\d+>/

  defp translatable?(content) do
    content = content || ""

    stripped =
      content
      |> String.replace(@url_regex, " ")
      |> String.replace(@mention_regex, " ")
      |> strip_code_blocks()

    words = String.split(stripped, ~r/\s+/u, trim: true)

    # Needs at least 2 words of actual prose after removing noise.
    length(words) >= 2
  end

  defp strip_code_blocks(text) do
    text |> String.split("```") |> Enum.take_every(2) |> Enum.join(" ")
  end

  # -- Helpers --------------------------------------------------------------

  defp option(%Interaction{data: %{options: options}}, name) do
    case Enum.find(options || [], &(&1.name == name)) do
      nil -> ""
      %{value: value} -> value
      _ -> ""
    end
  end

  defp respond(interaction, content, ephemeral \\ false) do
    data = if ephemeral, do: %{content: content, flags: 64}, else: %{content: content}
    response = %{type: 4, data: data}

    case InteractionApi.create_response(interaction, response) do
      {:ok, _} ->
        :ok

      error ->
        Logger.warning("interaction response failed: #{inspect(error)}")
        :error
    end
  end

  defp ephemeral?(%Interaction{data: %{options: options}}) do
    case Enum.find(options || [], &(&1.name == "hidden")) do
      %{value: v} when v in [true, "true"] -> true
      _ -> false
    end
  end

  # Edit the deferred (type 5) response into the real answer.
  defp followup(interaction, content) do
    case InteractionApi.edit_response(interaction, %{content: content}) do
      {:ok, _} -> :ok
      error -> Logger.warning("followup failed: #{inspect(error)}")
    end
  end

  defp upload_file_followup(interaction, filename, content, from, to) do
    case InteractionApi.edit_response(interaction, %{
           content: "📄 Translated #{flag(from)} → #{flag(to)} — here's your file:",
           files: [%{name: filename, body: content}]
         }) do
      {:ok, _} -> :ok
      error -> Logger.warning("file followup failed: #{inspect(error)}")
    end
  end

  defp respond_message(%Message{} = msg, content) do
    case MessageApi.create(msg.channel_id, content: content) do
      {:ok, _} -> :ok
      error -> Logger.warning("auto-translate reply failed: #{inspect(error)}")
    end
  end

  defp flag(code), do: TranslateBot.Languages.flag(code)

  defp normalize_lang(lang) do
    case String.downcase(lang || "") do
      "es" -> "es"
      "spanish" -> "es"
      "español" -> "es"
      _ -> "en"
    end
  end

  defp language_name(lang), do: TranslateBot.Languages.name(lang)

  defp slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "page"
      s -> String.slice(s, 0, 50)
    end
  end
end
