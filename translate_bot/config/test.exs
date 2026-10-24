import Config

# Point the fallback chain at deterministic fakes — no network in tests.
config :translate_bot,
  backends: [
    TranslateBot.TestSupport.FailingBackend,
    TranslateBot.TestSupport.UpperBackend
  ],
  register_commands: false

config :nostrum,
  token: "MTIzNDU2Nzg5MDEyMzQ1Njc4.GdXx9x.AbCdEfGhIjKlMnOpQrStUvWxYz12345678",
  consumers: [TranslateBot.Consumer],
  # No voice support needed — suppresses startup warnings.
  youtubedl: false,
  streamlink: false

config :logger, level: :warning
