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
  max_translation_file_bytes: 1_000_000,
  register_commands: true
```

Persisted runtime state lives in `data/` (git-ignored): `channels.dets`
(`/auto` channel toggles) and `stats.dets` (usage counters).

---

## `TranslateBot.Consumer`

Nostrum consumer — the Discord-facing entry point. Supervised by
`TranslateBot.Application`.

| Event | Behaviour |
|---|---|
| `{:READY, _, _}` | Registers all 7 commands globally (idempotent) |
| `{:INTERACTION_CREATE, ...}` | Dispatches slash commands. Simple ones reply immediately (type 4, optional ephemeral `flags: 64`); `/translate-file` and `/translate-url` defer (type 5), translate in a `Task`, then edit the response with the translated file |
| `{:MESSAGE_CREATE, ...}` | In `/auto` channels: translate prose; text-file attachments (`.txt .md .csv .srt .html .json .log`) go through `FileTranslator` and come back as translated files. Ignores bots, URLs, mentions, code blocks, <2-word messages |
| `{:MESSAGE_REACTION_ADD, ...}` | Flag-emoji reactions (see `Languages`) translate that message into the flag's language; 30s dedupe per (message, lang) |
| anything else | `:ignore` |

## `TranslateBot.Translation`

Orchestrator: stats → cache → backend chain → cache.

```elixir
TranslateBot.Translation.translate("hello", "en", "es", channel_id: 123)
#=> {:ok, "hola", :fresh}          # third element: :fresh | :cached

TranslateBot.Translation.auto("¿cómo estás?", channel_id: 123)
#=> {:ok, %{from: "es", to: "en", text: "how are you?", origin: :fresh}}

TranslateBot.Translation.translate("hi", "en", "en")
#=> {:error, :same_language}
```

`channel_id` is optional (used for stats attribution). Fresh translations bump
`Stats` counters; cache hits bump `record_cache_hit/0`.

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

- `translate/3` — `POST {LIBRETRANSLATE_URL}/translate` with
  `%{q, source, target, format: "text"}` (+ optional `api_key`). `source` may
  be `"auto"` for server-side detection.
- `detect/1` — `POST /detect` with `%{q}` → `{:ok, code}` (e.g. `"zh-Hans"`)

## `TranslateBot.Translators.DeepL`

`POST {endpoint}/v2/translate` with `DeepL-Auth-Key` header. Endpoint is
`api-free.deepl.com` when the key ends in `:fx`, else `api.deepl.com`.
Omitting `source_lang` (i.e. passing `"auto"`) makes DeepL detect it
server-side. `available?/0` is `false` without a key, so it's skipped.

## `TranslateBot.Cache`

ETS translation cache. Keys are `{text, source, target}` — direction-aware.

- `fetch/3` → `{:ok, text} | :miss`
- `put/4`, `clear/0`, `size/0`
- TTL via `:cache_ttl_ms` (default 1h); lazy expiry on read + sweep every 10 min

## `TranslateBot.Channels`

Per-channel `/auto` state — **persisted to DETS** (`data/channels.dets`),
so toggles survive restarts.

- `enabled?/1` → boolean (safe pre-table)
- `toggle/1` → new boolean state
- `count/0` → number of channels with auto-translate on

## `TranslateBot.Detect`

Language detection with two tiers.

- `detect/1` → `"es" | "en"` — offline heuristics: Spanish accent characters
  decide immediately, otherwise stop-word majority; defaults to `"en"`
- `rich/1` → `{:ok, code} | {:error, _}` — any language. Latin-script text
  uses the local heuristics; other scripts (Chinese, Japanese, Cyrillic, …)
  fall through to LibreTranslate's `/detect`
- `other/1` → flips es/en

## `TranslateBot.Languages`

Flag emoji ↔ language-code metadata.

- `from_flag/1` — `"🇨🇳"` → `"zh-Hans"` (`nil` if unknown); ~40 flags supported
- `flag/1` — code → flag (`"en"` → `"🇬🇧"`, unknown → `"🌐"`)
- `name/1` — code → display name (`"zh-Hans"` → `"Chinese (Simplified)"`)
- `flags/0` — the full map (tests/introspection)

## `TranslateBot.FileTranslator`

Chunked text-file translation pipeline.

- `run(attachment, opts)` — download Discord attachment → UTF-8 check → size
  check → detect source → translate → `{:ok, %{filename, content, from, to}}`.
  `opts: [to: "fr"]` forces a target; otherwise English → Spanish, everything
  else → English. Errors: `:file_too_large` (over `:max_translation_file_bytes`,
  default 1 MB), `:invalid_utf8`, `:detection_failed`, `{:download, _}`
- `translate_text(text, from, to)` — the chunk pipeline without any download;
  shared with `UrlTranslator`
- `chunk_lines/1` — split into whole-line chunks under 2,000 chars
  (hard-split for oversized lines); public for tests
- `text_file?/1` — is this attachment a translatable text file?

## `TranslateBot.UrlTranslator`

`run(url, opts)` — fetch a page (redirects followed, 15s timeout) → extract
`<title>` + readable text (dependency-free readability: strips
script/style/head/nav/footer, block tags become newlines, decodes common
HTML entities) → same size/detect/translate pipeline as files.
Returns `{:ok, %{title, content, from, to}}`. Errors: `:not_html`,
`:no_readable_text` (<40 chars), `{:http, status}`, `:file_too_large` (2 MB).

## `TranslateBot.Stats`

Usage counters, **persisted to DETS** (`data/stats.dets`). Never blocks or
crashes translation flows (all bumps are rescue-safe).

- `record_translation(source, target, channel_id)` — fresh translation
- `record_cache_hit/0`
- `snapshot/0` → `%{total: n, cache_hits: n, langs: %{{src, tgt} => n}, channels: %{id => n}}`

## `TranslateBot.Commands`

Command definitions + registration.

- `register/0` — idempotent global registration via
  `Nostrum.Api.ApplicationCommand.create_global_command/2`; logs each success
- `all/0` — the raw command maps (used in tests)

### Command shapes

```
/translate       text:<string, required>  hidden:<bool, optional>
/translate-to    lang:<choice, required>  text:<string, required>
/translate-file  file:<attachment, required>  lang:<choice, optional>
/translate-url   url:<string, required>   lang:<choice, optional>
/detect          text:<string, required>
/auto            (no options)
/stats           (no options)
```

`lang` choices come from a shared 25-language list (Discord caps dropdowns
at 25), a subset of the ~40 reaction flags.
