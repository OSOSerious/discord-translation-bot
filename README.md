# TranslateBot

**English ↔ Spanish translation bot for Discord, written in Elixir.**

Self-hostable, private, and fast: slash commands for one-off translations plus an opt-in per-channel auto-translate mode. Translations are cached in ETS, and the translation backend is pluggable (DeepL, LibreTranslate, or write your own).

## Features

- `/translate text:<msg>` — auto-detects ES/EN and translates to the other language
- `/detect text:<msg>` — reports whether the message looks Spanish or English
- `/auto` — toggles auto-translate for the current channel (every message gets translated)
- **Pluggable backends** — tries DeepL first if configured, falls back to LibreTranslate
- **ETS cache** — repeated phrases never hit the API twice (1h TTL)
- **Language detection** — offline heuristics (accent characters + stop-word analysis), no network needed

## Requirements

- Elixir ~> 1.14 (developed on 1.19 / OTP 28)
- A [Discord application](https://discord.com/developers/applications) with a bot token
- One translation backend:
  - [LibreTranslate](https://libretranslate.com) self-hosted via Docker (**fully local/private**), or
  - A [DeepL API key](https://www.deepl.com/pro-api) (free tier: 500k chars/month)

## Setup

### 1. Discord application

1. Create an app at the [Developer Portal](https://discord.com/developers/applications) → **Bot** tab → copy the **token**
2. Enable **Message Content Intent** under *Privileged Gateway Intents* (required for `/auto`)
3. Invite it to your server with `bot` + `applications.commands` scopes and permissions `117760`
   (View Channels, Send Messages, Embed Links, Attach Files, Read Message History)

### 2. Configuration

Create a `.env` file (already git-ignored):

```bash
DISCORD_BOT_TOKEN=your-bot-token

# Backend option A — self-hosted LibreTranslate (recommended, fully private)
docker run -d --name libretranslate -p 5100:5000 libretranslate/libretranslate
LIBRETRANSLATE_URL=http://localhost:5100

# Backend option B — DeepL (uncomment and drop the LibreTranslate lines)
# DEEPL_API_KEY=your-key:fx
```

> ⚠️ **macOS note:** port 5000 is taken by AirPlay Receiver (ControlCenter).
> Map LibreTranslate to a different host port, e.g. `-p 5100:5000` as above.

### 3. Run

```bash
mix deps.get
set -a; source .env; set +a   # or use direnv / dotenv
mix run --no-halt
```

On boot you'll see:

```
[info] READY
[info] registered /translate
[info] registered /detect
[info] registered /auto
```

Type `/translate text: hola` in your server to test.

## Usage

| Command | What it does |
|---|---|
| `/translate text: good morning` | Detects English → replies `🇬🇧 → 🇪🇸: buenos días` |
| `/translate text: ¿cómo estás?` | Detects Spanish → replies `🇪🇸 → 🇬🇧: how are you?` |
| `/detect text: hola` | Replies `That looks like **Spanish** 🇪🇸` |
| `/auto` | Toggles auto-translate on/off for the current channel |

## Architecture

```
Discord Gateway ──> Nostrum Consumer (TranslateBot.Consumer)
                        │
                        ├──> TranslateBot.Translation (orchestrator)
                        │       ├──> TranslateBot.Cache (ETS, 1h TTL)
                        │       └──> Backend fallback chain:
                        │             DeepL ──> LibreTranslate ──> (your own)
                        ├──> TranslateBot.Detect (offline ES/EN heuristics)
                        └──> TranslateBot.Channels (per-channel /auto state, ETS)
```

See [API.md](API.md) for the full module reference.

## Development

```bash
mix deps.get
mix test                     # 14 tests, no network needed (fake backends)
mix compile --warnings-as-errors
```

Tests run with `--no-start` (see `mix.exs` aliases) so Nostrum never opens a
gateway connection; translation backends are swapped for deterministic fakes
in `config/test.exs`.

## License

MIT — see [LICENSE](LICENSE).
