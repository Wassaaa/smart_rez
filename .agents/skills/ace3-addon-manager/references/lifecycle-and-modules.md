# Lifecycle and Modules

## AceAddon-3.0

- Use `LibStub("AceAddon-3.0"):NewAddon(...)` for the addon root.
- Use `:NewModule(...)` only for real feature boundaries, optional subsystems, or lifecycle-isolated behavior.
- Keep `OnInitialize` for DB creation, migrations, options registration, and slash-command registration.
- Keep `OnEnable` for runtime work that depends on the game state already being present.
- Treat `OnDisable` as an explicit unwind path. If the addon cannot truly stop cleanly, avoid pretending it can.

## AceConsole-3.0

- Use `RegisterChatCommand` for slash entrypoints.
- Prefer one command dispatcher that handles subcommands clearly.
- If the addon surface is already modeled as an options table, AceConfig command registration can replace custom parsing for simple cases.

## AceEvent-3.0

- Use `RegisterEvent` for Blizzard events.
- Use `RegisterMessage` and `SendMessage` for internal addon messages.
- Prefer embedding AceEvent into the addon object so events and messages clean up naturally on disable.

## AceHook-3.0

- Default to `SecureHook` for post-call integration.
- Use `Hook` or `RawHook` only when a post-hook is insufficient.
- Unhook aggressively when the addon has a real disable path or when the target UI can be torn down and rebuilt.

## AceTimer-3.0

- Use `ScheduleTimer` for one-shot delayed work and `ScheduleRepeatingTimer` for polling or cadence-based behavior.
- Store timer handles when they live longer than a tiny local workflow.
- Cancel timers when the state they depend on changes, and call `CancelAllTimers` if disable should stop the subsystem entirely.

## AceBucket-3.0

- Use buckets when an event can fire in bursts and the addon only needs a consolidated update.
- Favor bucketing high-volume state refreshes over manual debounce code.
- Re-check whether a simple timer or direct event registration would be easier before adding a bucket.

## AceComm-3.0 and AceSerializer-3.0

- Use `RegisterComm` and `SendCommMessage` for addon-channel traffic.
- Keep prefixes short and stable. The docs cap them at 16 printable characters.
- Pair AceComm with `AceSerializer-3.0` for table payloads or anything more complex than a tiny fixed string.
- Treat deserialization failures as real input-validation events, not impossible states.

## AceLocale-3.0

- Register the default locale first with `NewLocale(..., true)`.
- Retrieve localized strings with `GetLocale`.
- Keep locale keys stable and semantic. Do not key off full English sentences that are likely to churn every refactor.

## Practical sequencing

- Add the library to packaging and load order first.
- Embed it into the addon only if the ergonomic methods belong on the addon object.
- Add the smallest amount of lifecycle state needed for the feature.
- Verify the change with a repo audit after wiring the library.
