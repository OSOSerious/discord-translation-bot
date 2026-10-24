# Research: English ↔ Spanish Discord Bot in Elixir

_Date: 2026-10-23_

## 1. Discord library choice

**Nostrum** (https://github.com/Kraigie/nostrum) is the de-facto standard Discord
library for Elixir — an actively maintained wrapper over the Discord Gateway
(WebSocket) + REST API, with caching, sharding, and slash-command support.

- Install: `{:nostrum, "~> 0.8"}` (hex.pm; requires Elixir ~> 1.14, OTP 25+)
- Pattern: you start a **Consumer** (GenServer) that receives `handle_event/1`
  callbacks — most importantly `:MESSAGE_CREATE` and `:INTERACTION_CREATE`.
- Alternatives (all weaker options today):
  - `coxir` — abandoned/unmaintained
  - `discord_elixir` / older forks — stale
  - Rolling your own Gateway client — not worth it; Nostrum handles
    heartbeats, resume, rate limits, and cache.

### Minimal Nostrum consumer

```elixir
defmodule TranslateBot.Consumer do
  use Nostrum.Consumer

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    # translate logic here
    :ignore
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    # slash command /translate text:"hello"
    Nostrum.Api.InteractionResponse.ack(interaction) # or create with data
    :ignore
  end

  def handle_event(_), do: :ignore
end
```

Add to supervision tree:

```elixir
children = [TranslateBot.Consumer]
Supervisor.start_link(children, strategy: :one_for_one)
```

Config (config/config.exs):

```elixir
config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN")
```

## 2. Translation backends (ranked for this use case)

| Option | Free tier | Quality ES↔EN | Notes |
|---|---|---|---|
| **LibreTranslate** | Yes (self-host unlimited; public instance rate-limited) | Good | AGPLv3, v1.9.6, self-hostable Docker, offline capable. Best free/privacy option. |
| **DeepL API Free** | 500k chars/month | Excellent (best for ES/EN pair) | Free key required, no card. Simple REST. |
| **Google Cloud Translation v2** | $ credit / ~500k chars free eval | Excellent | Official Elixir client exists: `google_api_translate` on Hex. |
| **MyMemory API** | ~5k words/day anonymous | OK | Zero signup, good for hobby bot. |
| **LLM (OpenAI/Ollama)** | Ollama = free/local | Excellent w/ good prompt | Heavier, slower; great if you want tone/context awareness. |

### LibreTranslate API (verified from libretranslate.com)

- `POST /translate` with JSON: `{"q": "hello", "source": "en", "target": "es", "format": "text"}`
- Public instance requires an API key for sustained use; **self-hosting via
  Docker removes limits** (`libretranslate/libretranslate` image, port 5000).

### DeepL (free tier)

- `POST https://api-free.deepl.com/v2/translate`
  body: `{"text": "hello", "target_lang": "ES"}`, header `Authorization: DeepL-Auth-Key <key>`

## 3. Recommended architecture

```
Discord Gateway ──> Nostrum Consumer
                       │
                       ├──> Translator (behaviour)
                       │      ├── LibreTranslateClient (Req)
                       │      ├── DeepLClient (Req)
                       │      └── (fallback chain via GenServer)
                       │
                       ├──> Cache (ETS, key = hash(text+src+tgt), TTL)
                       │
                       └──> Nostrum.Api.create_message / interaction response
```

Key Elixir fit points:

- **Req** (`{:req, "~> 0.5"}`) for HTTP — modern, built on Finch, retries built in.
- **ETS via `:ets`** for a translation cache — avoids burning API quota on
  repeated phrases (Discord servers repeat words a lot).
- **GenServer fallback chain**: try DeepL → on 429/failure fall back to
  LibreTranslate → MyMemory. Cheap resilience.
- **Slash commands** (`/translate`, `/detect`) registered once at boot via
  `Nostrum.Api.ApplicationCommand.create_global_command/2` — better UX than
  prefix commands and no mention-spam.
- Auto-translate mode per channel: keep channel state in ETS
  (`channel_id -> {src, tgt}`), checked in `:MESSAGE_CREATE`.

## 4. Suggested mix.exs deps

```elixir
defp deps do
  [
    {:nostrum, "~> 0.8"},
    {:req, "~> 0.5"},
    {:jason, "~> 1.4"}
  ]
end
```

## 5. Risks / gotchas

1. Nostrum version churn — pin the version, read the changelog between upgrades.
2. Discord rate limits — Nostrum handles REST limits, but don't translate
   every message in busy channels without caching + debounce.
3. LibreTranslate public instance requires API key + has char limits
   (~charactersLimit per request); self-host to avoid.
4. Message content intent must be enabled in the Discord Developer Portal
   (Privileged Gateway Intents) or `MESSAGE_CREATE` content is empty.
5. Never commit the bot token — runtime env only (`System.get_env`).
