# Changelog

All notable changes to this project are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-10-25

The "everything Discord" release: any-language reactions, URL translation,
usage stats, persistent state, ephemeral replies.

### Added
- **Any-flag reaction translation** — react with ~40 flag emojis (🇨🇳 🇫🇷 🇩🇪
  🇯🇵 🇷🇺 🇰🇷 🇮🇹 🇵🇹 …) on any message to translate it into that language;
  non-Latin scripts routed through LibreTranslate's detector; 30s dedupe —
  `TranslateBot.Languages` + Consumer
- **`/translate-url url: lang:`** — fetches a web page, extracts readable
  text (no-dependency readability pass), translates, returns `title.lang.txt` —
  `TranslateBot.UrlTranslator`
- **`/stats`** — total translations, cache hits, auto-channels on, top
  language pairs
- **Persistent state** — `/auto` channel toggles and stats counters survive
  restarts via DETS (`data/channels.dets`, `data/stats.dets`)
- **Ephemeral replies** — optional `hidden:` flag on `/translate` makes the
  answer visible only to the caller (Discord `flags: 64`)
- **Channel attribution** — `Translation.translate/4` and `auto/2` accept a
  `channel_id` so stats know where translations came from

## [0.2.0] — 2026-10-24

Multi-language file translation + `/translate-file` command.

### Added
- **Multi-language file translation** — drop a text file in an `/auto`
  channel and get it back translated; auto-detects any of LibreTranslate's
  50 languages (Chinese/Japanese/Cyrillic via backend detector, Latin
  scripts via local heuristics); everything → English, English → Spanish —
  `TranslateBot.FileTranslator`
- **`/translate-file file: lang:`** — upload the file right in the command;
  deferred response (type 5) edited into the translated file; optional
  25-language dropdown
- More file types in `/auto` channels: `.md` `.csv` `.srt` `.html` `.json` `.log`
- `/translate-to` forced-direction command with language dropdown
- `Detect.rich/1` — any-language detection with script-based routing
- LibreTranslate `detect/1` client (`/detect` endpoint)
- DeepL `source_lang` auto-detection when source is `"auto"`
- Chunked file translation: whole-line chunks under 2,000 chars, hard-split
  for oversized lines, BOM stripping, UTF-8 validation

### Fixed
- macOS port 5000 is occupied by AirPlay Receiver (ControlCenter); README
  now documents publishing LibreTranslate on 5100 instead

## [0.1.0] — 2026-10-24

First working release.

### Added
- Discord bot via Nostrum: gateway consumer with reconnect/shard handling
- Slash commands `/translate`, `/detect`, `/auto` — auto-registered on
  gateway `READY`, idempotent on every boot
- Auto-detect ES↔EN translation with offline heuristics
  (accent characters + stop-word majority) — `TranslateBot.Detect`
- Pluggable translation backend behaviour (`TranslateBot.Translator`) with
  DeepL and LibreTranslate clients and automatic fallback chain
- DeepL free-tier support: keys ending in `:fx` route to `api-free.deepl.com`
- ETS translation cache with direction-aware keys, 1h TTL, lazy expiry and
  periodic sweeps — `TranslateBot.Cache`
- Per-channel auto-translate toggle backed by ETS — `TranslateBot.Channels`
- Reaction translation with 🇬🇧/🇪🇸 flags
- Smart skip in auto channels (URLs, mentions, code blocks, <2-word messages)
- Test suite with deterministic fake backends; runs fully offline
  via `--no-start` alias

### Fixed
- Command registration never ran on boot: `start_phase/3` was defined but the
  application spec lacked `start_phases`, so the phase was silently skipped.
  Registration now lives in the Consumer's `{:READY, _, _}` handler.
- Tests crashed with "Authentication rejected, invalid token": Nostrum tried
  a real gateway connect under `mix test`. Fixed with a dummy-format token in
  `config/test.exs` plus a `test --no-start` alias.

### Notes
- On macOS, host port 5000 is occupied by AirPlay Receiver (ControlCenter).
  Self-hosted LibreTranslate must be published on a different port
  (e.g. `-p 5100:5000`) and referenced via `LIBRETRANSLATE_URL`.
