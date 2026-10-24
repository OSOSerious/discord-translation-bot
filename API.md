# API Reference

Internal module documentation for TranslateBot. Public configuration goes
through **environment variables** (see below) — no module needs to be called
directly to run the bot.

---

## Configuration (environment variables)

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DISCORD_BOT_TOKEN` | ✅ | — | Bot token from the Discord Developer Portal |
| `LIBRETRANSLATE_URL` | — | `http://localhost:5000` | Base URL of a LibreTranslate instance |
| `LIBRETRANSLATE_API_KEY` | — | — | API key (only needed for public instances) |
| `DEEPL_API_KEY` | — | — | DeepL key; keys ending in `:fx` auto-use the free endpoint |

Backend precedence: **DeepL first** (if key present), then LibreTranslate.
A backend without credentials is skipped automatically.

Application-level overrides (in `config/*.exs`):

```elixir
config :translate_bot,
  backends: [TranslateBot.Translators.DeepL, TranslateBot.Translators.LibreTranslate],
  cache_ttl_ms: :timer.hours(1),
  register_commands: true
```

---

## `TranslateBot.Consumer`

Nostrum consumer — the Discord-facing entry point. Supervised by
`TranslateBot.Application`.

| Event | Behaviour |
|---|---|
| `{:READY, _, _}` | Registers `/translate`, `/detect`, `/auto` globally (idempotent) |
| `{:INTERACTION_CREATE, ...}` | Dispatches slash commands, responds via `Nostrum.Api.Interaction.create_response/2` (type 4) |
| `{:MESSAGE_CREATE, ...}` | If `/auto` is on for the channel: detect + translate + reply. Ignores bots and empty content |
| anything else | `:ignore` |

## `TranslateBot.Translation`

Orchestrator: cache → backend chain → cache.

```elixir
TranslateBot.Translation.translate("hello", "en", "es")
#=> {:ok, "hola", :fresh}          # third element: :fresh | :cached

TranslateBot.Translation.auto("¿cómo estás?")
#=> {:ok, %{from: "es", to: "en", text: "how are you?", origin: :fresh}}

TranslateBot.Translation.translate("hi", "en", "en")
#=> {:error, :same_language}
```

## `TranslateBot.Translator` (behaviour)

Implement two callbacks to add a backend:

```elixir
defmodule MyBackend do
  @behaviour TranslateBot.Translator

  @impl true
  def available?, do: System.get_env("MY_KEY") != nil

  @impl true
  def translate(text, source, target) do
    ...  # {:ok, translated} | {:error, reason}
  end
end
```

Then put it in the chain:

```elixir
config :translate_bot, backends: [MyBackend, TranslateBot.Translators.LibreTranslate]
```

## `TranslateBot.Translators.LibreTranslate`

`POST {LIBRETRANSLATE_URL}/translate` with `%{q, source, target, format: "text"}`
(+ optional `api_key`). Returns `{:ok, translatedText}` on 200.

## `TranslateBot.Translators.DeepL`

`POST {endpoint}/v2/translate` with `DeepL-Auth-Key` header. Endpoint is
`api-free.deepl.com` when the key ends in `:fx`, else `api.deepl.com`.
`available?/0` is `false` without a key, so it's skipped in the chain.

## `TranslateBot.Cache`

ETS translation cache. Keys are `{text, source, target}` — direction-aware.

- `fetch/3` → `{:ok, text} | :miss`
- `put/4`, `clear/0`, `size/0`
- TTL via `:cache_ttl_ms` (default 1h); lazy expiry on read + sweep every 10 min

## `TranslateBot.Channels`

Per-channel `/auto` state in ETS.

- `enabled?/1` → boolean (safe pre-table)
- `toggle/1` → new boolean state

## `TranslateBot.Detect`

Offline ES/EN detection, no network.

- `detect/1` → `"es" | "en"` — accent characters decide immediately,
  otherwise stop-word majority; defaults to `"en"`
- `other/1` → flips the language

## `TranslateBot.Commands`

Command definitions + registration.

- `register/0` — idempotent global registration via
  `Nostrum.Api.ApplicationCommand.create_global_command/2`; logs each success
- `all/0` — the raw command maps (used in tests)

### Command shapes

```
/translate  text:<string, required>
/detect     text:<string, required>
/auto       (no options)
```
