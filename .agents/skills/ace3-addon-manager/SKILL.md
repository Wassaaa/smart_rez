---
name: ace3-addon-manager
description: Audit, design, refactor, and extend World of Warcraft addons built with Ace3. Use when Codex needs to inspect or modify Ace3-based addons; choose or wire AceAddon-3.0, AceConsole-3.0, AceEvent-3.0, AceDB-3.0, AceDBOptions-3.0, AceConfig-3.0, AceConfigDialog-3.0, AceConfigRegistry-3.0, AceGUI-3.0, AceHook-3.0, AceTimer-3.0, AceBucket-3.0, AceComm-3.0, AceSerializer-3.0, AceLocale-3.0, or AceTab-3.0; update `.toc` or `embeds.xml`; add SavedVariables, slash commands, options panels, custom AceGUI windows, hooks, timers, buckets, comms, serialization, localization, profiles, or module structure; or reconcile vendored Ace libraries with actual Lua usage.
---

# Ace3 Addon Manager

## Quick Start

1. Run `python scripts/audit_ace3_addon.py <addon-root>` before editing.
2. Read only the reference file that matches the task:
   - `references/lifecycle-and-modules.md` for addon shape, modules, events, slash commands, hooks, timers, buckets, comms, serialization, and localization.
   - `references/config-ui-and-db.md` for SavedVariables, profiles, options tables, Blizzard settings integration, AceGUI, and AceTab.
   - `references/source-map.md` for official Ace3 docs, packaging links, and the research snapshot.
3. Keep `.toc`, `embeds.xml`, vendored `Libs/`, and Lua `LibStub(...)` usage aligned in the same change.

## Workflow

### 1. Audit before changing code

- Inspect the addon root, `.toc`, `embeds.xml`, vendored `Libs/`, and every local `LibStub(...)` or `:NewAddon(...)` reference first.
- Prefer the smallest Ace3 surface that solves the problem. Do not add libraries "just in case."
- Use the audit script output to spot mismatches:
  - referenced in Lua but not loaded from TOC/XML
  - vendored locally but never loaded
  - loaded but only indirectly used
  - missing SavedVariables declarations for `AceDB-3.0`

### 2. Choose the right Ace3 libraries

- Start with `AceAddon-3.0`.
- Add `AceConsole-3.0` for slash commands and chat-facing control.
- Add `AceEvent-3.0` for Blizzard events or internal addon messages.
- Add `AceDB-3.0` for persistent state, and `AceDBOptions-3.0` when profile management belongs in the options UI.
- Add `AceConfig-3.0`, `AceConfigDialog-3.0`, and `AceConfigRegistry-3.0` for options tables and Blizzard settings integration.
- Add `AceGUI-3.0` only when a custom window is warranted and the options table UI is not enough.
- Add `AceHook-3.0`, `AceTimer-3.0`, or `AceBucket-3.0` for reactive behavior.
- Add `AceComm-3.0` plus `AceSerializer-3.0` together for structured addon traffic.
- Add `AceLocale-3.0` when user-facing strings need translation.
- Treat `AceTab-3.0` as niche. The official docs say it is not yet finalized, so inspect current source before adopting it.

### 3. Implement with Ace3-native patterns

- Put DB creation, migrations, option registration, and slash-command registration in `OnInitialize`.
- Put live game-state work in `OnEnable`: registering events, starting timers, establishing hooks, opening comm channels, and building active UI state.
- Only implement `OnDisable` when the addon can really unwind work. If you do, cancel timers, unhook, hide or release transient UI, and stop messages or traffic cleanly.
- Use `self.db.profile` for shared user settings, `self.db.char` for character state, and broader scopes only when the feature truly needs them.
- When options change state that is shown in AceConfig UIs, call `AceConfigRegistry:NotifyChange(appName)`.
- For AceGUI:
  - set a layout on every container
  - set widths explicitly on widgets unless `SetFullWidth` or `SetFullHeight` is intended
  - release transient windows on close when they are disposable
  - call `ReleaseChildren()` before rebuilding dynamic tab or scroll content
- Prefer `SecureHook` over `Hook` or `RawHook` unless you need pre-call behavior or full replacement.
- Prefer `AceDBOptions-3.0` over hand-rolled profile controls.
- Serialize non-trivial comm payloads instead of building custom string protocols.

### 4. Keep load order and packaging correct

- If the addon vendors Ace3 locally, keep `.toc` and `embeds.xml` consistent with the libraries actually used.
- If packaging through `.pkgmeta`, prefer referencing only the specific Ace3 libraries in use, not the entire framework bundle.
- When `AceConfig-3.0` is embedded through its top-level XML, remember that it pulls in subcomponents such as `AceConfigRegistry-3.0`, `AceConfigCmd-3.0`, and `AceConfigDialog-3.0`.

### 5. Validate after edits

- Re-run `python scripts/audit_ace3_addon.py <addon-root>`.
- Search for missing or stale library references with `rg`.
- Confirm the SavedVariables names in `.toc` match the names passed to `AceDB-3.0`:New.
- Confirm the options entrypoint still opens correctly, especially after `AddToBlizOptions`.
- If the user asks for the latest Ace3 release or docs status, browse the official overview and relevant API page again instead of assuming the snapshot in this skill is current.

## Common Tasks

### Add or refactor addon core

- Use `AceAddon-3.0` as the root object.
- Split real subsystems into `:NewModule(...)` modules only when they benefit from lifecycle isolation or optional enable or disable behavior.
- Keep reusable pure-Lua helpers out of Ace modules unless they need lifecycle state.

### Add settings, profiles, or custom UI

- Read `references/config-ui-and-db.md`.
- Use options tables first.
- Reach for custom `AceGUI-3.0` windows when the UX needs richer layouts, dynamic content, or workflows that the options table model does not express well.
- Add `AceDBOptions-3.0` unless there is a specific reason to manage profiles manually.

### Add reactive or cross-client behavior

- Read `references/lifecycle-and-modules.md`.
- Use `AceEvent-3.0` for game events, `AceHook-3.0` for integration points, `AceTimer-3.0` for delayed or repeating work, `AceBucket-3.0` for event coalescing, and `AceComm-3.0` plus `AceSerializer-3.0` for addon channel data.
- If strings are user-facing, wire them through `AceLocale-3.0` before expanding the feature further.

## Resources

### `scripts/audit_ace3_addon.py`

Run this first when the request involves an existing addon. It reports TOC metadata, vendored libraries, libraries loaded through TOC or XML recursion, local Lua references, feature signals, and likely gaps.

### `references/lifecycle-and-modules.md`

Read for lifecycle, module boundaries, events, console, hooks, timers, buckets, comms, serialization, and localization.

### `references/config-ui-and-db.md`

Read for `AceDB-3.0`, `AceDBOptions-3.0`, `AceConfig-3.0`, `AceConfigDialog-3.0`, `AceConfigRegistry-3.0`, `AceGUI-3.0`, and `AceTab-3.0`.

### `references/source-map.md`

Read when you need the official URL for a library, tutorial, or packaging source, or when the user asks for current Ace3 release information.
