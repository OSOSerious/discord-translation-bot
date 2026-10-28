import Config

# Nostrum (Discord) configuration.
# Never commit the token — read it from the environment at runtime.
config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN"),
  # /auto and flag reactions read message text, which needs the privileged
  # Message Content intent (also switch it on in the Developer Portal, Bot tab).
  gateway_intents: [:guilds, :guild_messages, :guild_message_reactions, :message_content]

# Translation backends, tried in order until one succeeds.
# DeepL is skipped automatically when no API key is configured.
config :translate_bot,
  backends: [
    TranslateBot.Translators.DeepL,
    TranslateBot.Translators.LibreTranslate
  ],
  libre_translate_url: System.get_env("LIBRETRANSLATE_URL", "http://localhost:5000"),
  libre_translate_key: System.get_env("LIBRETRANSLATE_API_KEY"),
  deepl_key: System.get_env("DEEPL_API_KEY"),
  cache_ttl_ms: :timer.hours(1),
  register_commands: true

if config_env() == :test do
  import_config "test.exs"
end
