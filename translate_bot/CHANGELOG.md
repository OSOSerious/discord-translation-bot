# Changelog

All notable changes to this project are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Test suite (14 tests) with deterministic fake backends; runs fully offline
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
