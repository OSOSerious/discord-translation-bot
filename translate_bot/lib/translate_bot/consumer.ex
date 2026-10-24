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

  def handle_event(_event), do: :ignore

  # -- Interactions ---------------------------------------------------------

  defp handle_interaction(%Interaction{data: %{name: "translate"}} = interaction) do
    text = option(interaction, "text")

    case TranslateBot.Translation.auto(text) do
      {:ok, %{from: from, to: to, text: translated}} ->
        respond(interaction, "**#{flag(from)} → #{flag(to)}:** #{translated}")

      {:error, :empty_text} ->
        respond(interaction, "Give me something to translate! `/translate text: hola`")

      {:error, reason} ->
        Logger.error("translate failed: #{inspect(reason)}")
        respond(interaction, "Translation failed — try again in a moment.")
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

  defp handle_reaction(%MessageReactionAdd{emoji: %{name: emoji_name}} = reaction)
       when emoji_name in ["🇬🇧", "🇪🇸", " gb", "es"] do
    target = if emoji_name in ["🇬🇧", "en"], do: "en", else: "es"

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

  defp handle_reaction(_other), do: :ignore

  defp translate_reacted(content, target, reaction) do
    source = TranslateBot.Detect.detect(content)

    if source == target do
      # Already in the requested language — nothing to do.
      :ignore
    else
      case TranslateBot.Translation.translate(content, source, target) do
        {:ok, translated, _origin} ->
          respond_message(%Message{
            channel_id: reaction.channel_id,
            author: %{bot: false}
          }, "**#{flag(source)} → #{flag(target)}:** #{translated}")

        {:error, reason} ->
          Logger.warning("reaction translate failed: #{inspect(reason)}")
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

  defp respond(interaction, content) do
    response = %{type: 4, data: %{content: content}}

    case InteractionApi.create_response(interaction, response) do
      {:ok, _} ->
        :ok

      error ->
        Logger.warning("interaction response failed: #{inspect(error)}")
        :error
    end
  end

  defp respond_message(%Message{} = msg, content) do
    case MessageApi.create(msg.channel_id, content: content) do
      {:ok, _} -> :ok
      error -> Logger.warning("auto-translate reply failed: #{inspect(error)}")
    end
  end

  defp flag("es"), do: "🇪🇸"
  defp flag("en"), do: "🇬🇧"
  defp flag(_), do: "🌐"

  defp normalize_lang(lang) do
    case String.downcase(lang || "") do
      "es" -> "es"
      "spanish" -> "es"
      "español" -> "es"
      _ -> "en"
    end
  end

  defp language_name("es"), do: "Spanish"
  defp language_name("en"), do: "English"
  defp language_name(other), do: other
end
