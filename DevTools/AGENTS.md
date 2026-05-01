# DevTools/AGENTS.md

## Scope

`DevTools/` owns local WoWLua probes and development-only scripts. These files are for investigation and should not affect runtime behavior unless deliberately promoted.

## Owned Files

- `wowlua_recipe_probe.lua`: local recipe/profession probe.

## Contracts

- Do not add `DevTools/` files to `smart_rez.toc`.
- Keep probes targeted, readable, and easy to paste/run in the live game when needed.
- Prefer user-provided live-game `/dump`, `/eventtrace`, or `/run print(...)` outputs as stronger evidence than assumptions.
- If a probe becomes runtime functionality, move it to the correct runtime layer and update `smart_rez.toc` plus the relevant `AGENTS.md`.

## Child Documentation

No child `AGENTS.md` files exist yet.

## Doc Updates

Update this file when probe conventions, development-only script ownership, or promotion rules change.
