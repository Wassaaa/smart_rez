# Annotations/AGENTS.md

## Scope

`Annotations/` owns LuaLS annotation files and optional global declarations. These files support editor/type-checking behavior only.

## Owned Files

- `acegui.lua`: AceGUI widget and container annotations.
- `addon-globals.lua`: optional addon globals and integration globals.

## Contracts

- Do not add annotation-only files to `smart_rez.toc`.
- Prefer precise annotations over warning suppression.
- Keep annotations aligned with actual runtime surfaces; do not invent APIs to satisfy diagnostics.
- Add optional addon globals here when integration code references globals exposed by Auctionator, TSM, or similar addons.
- If live-game dumps contradict annotations, treat the dump as stronger evidence and update annotations.

## Child Documentation

No child `AGENTS.md` files exist yet.

## Doc Updates

Update this file when annotation file ownership changes, new optional globals are added, or LuaLS conventions change.
