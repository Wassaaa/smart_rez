# AGENTS.md

## Documentation First

DOCUMENTATION IS THE MOST IMPORTANT PART OF THIS PROJECT.

Documentation is the project memory, architecture contract, onboarding path, and agent safety rail. Treat every `AGENTS.md` file as binding guidance for the code under its directory, not as optional notes.

Poor documentation causes agent behavior drift, architecture drift, duplicated work, incorrect assumptions, and changes in the wrong layer. A code change that leaves known documentation drift behind is not done.

Before changing code, read:

1. the closest `AGENTS.md` for the files you will touch
2. every parent `AGENTS.md` up to the repository root
3. the root `AGENTS.md` index to discover sibling or child contracts that may apply.

This addon uses a documentation hierarchy:

- `/AGENTS.md` owns repo-wide rules, documentation policy, top-level architecture, Retail safety constraints, and the full `AGENTS.md` index.
- `/.agents/AGENTS.md` owns repo-local, tool-neutral agent assets and shared skills.
- `/Core/AGENTS.md` owns addon root state, shared helpers, slash commands, profession proxy, craft controller primitives, inventory scans, and binding helpers.
- `/Craft/AGENTS.md` owns reusable recipe-craft and salvage systems, craft/salvage storage, and craft action registration.
- `/Features/AGENTS.md` owns user-facing workflows that compose `Core/`, `Craft/`, `UI/`, and `Integrations/`.
- `/UI/AGENTS.md` owns AceConfig/AceGUI setup tabs, reusable components, custom windows, and display-scoped UI behavior.
- `/Integrations/AGENTS.md` owns optional addon adapters and integration-specific frame/API details.
- `/Annotations/AGENTS.md` owns LuaLS annotation contracts and optional addon globals.
- `/DevTools/AGENTS.md` owns local probes and scripts that must not load at runtime unless promoted deliberately.
- `/Legacy/AGENTS.md` owns retired or reference-only code that must not silently return to runtime load paths.

Always update documentation in the same session as code changes:

- update the closest owning `AGENTS.md` for changed files
- update parent docs when a change affects architecture, ownership, workflow, public contracts, load order, secure/profession behavior, or cross-cutting addon rules
- update this root index whenever an `AGENTS.md` file is added, removed, moved, or renamed
- create a nested `AGENTS.md` when a directory becomes a stable subsystem, feature family, UI surface, adapter family, test harness, or ownership boundary
- remove stale or contradictory instructions immediately
- keep implementation details in the closest local doc instead of bloating parent docs
- do not finish a change that leaves known documentation drift behind

`README.md` is public-facing. Architecture, workflow, ownership, and agent-facing implementation contracts belong in `AGENTS.md`.

## Documentation Shape

Every `AGENTS.md` should answer, in this order when practical:

1. what this scope owns
2. which files, directories, surfaces, or workflows it owns
3. which stable contracts it enforces
4. how child docs divide more specific detail
5. what changes require doc updates

Parent docs explain boundaries, ownership maps, stable contracts, and cross-cutting rules. Child docs explain concrete behavior, local file structure, state/config rules, APIs, commands, gotchas, and verification.

Do not create child docs for generated output, vendored dependency folders, build caches, tiny obvious directories, or temporary scratch areas.

## AGENTS File Index

This index must be exhaustive for repo `AGENTS.md` files:

- `/AGENTS.md`
- `/.agents/AGENTS.md`
- `/Annotations/AGENTS.md`
- `/Core/AGENTS.md`
- `/Craft/AGENTS.md`
- `/DevTools/AGENTS.md`
- `/Features/AGENTS.md`
- `/Integrations/AGENTS.md`
- `/Legacy/AGENTS.md`
- `/UI/AGENTS.md`

## Project

`smart_rez` is a Retail-only World of Warcraft addon for automation helpers, profession workflows, salvage/craft/disenchant logic, low-mode utilities, and integrations with Auctionator and TradeSkillMaster.

- Target modern Retail only. Treat `World of Warcraft: Midnight` as the active baseline.
- Prefer current namespaced APIs such as `C_Item.*`, `C_Container.*`, `C_TradeSkillUI.*`, and `Settings.*`.
- Do not preserve Classic or legacy compatibility unless explicitly requested.
- Keep owned code LuaLS-clean with annotations instead of warning suppression.
- Keep the addon lean: do not add frameworks, compatibility layers, global loaders, or broad rewrites without a clear request.

## Top-Level Architecture

Use a layered, reusable-module style:

- `Core/`: addon root, shared state, inventory/profession helpers, craft lock/controller helpers, profession proxy, bag restack, bindings, and slash commands.
- `Craft/`: reusable recipe-craft and salvage systems, craft/salvage config storage, craft action registrations.
- `Features/`: user-facing workflows such as Gold Printer, bag value, disenchant, low mode, warbank grab, AH selling/sniping, and probes.
- `UI/`: AceConfig/AceGUI windows, reusable UI components, feature setup tabs, and binding configuration UI.
- `Integrations/`: isolated adapters for optional or external addon APIs.
- `Annotations/`: LuaLS type and global annotations only.
- `DevTools/`: local WoWLua probes and development-only scripts.
- `Legacy/`: retired reference code only.
- `Libs/`: vendored third-party libraries. Do not edit unless intentionally updating vendored dependencies.
- `.agents/`: repo-local shared agent assets and skills. Do not add these files to the TOC.

Prefer reusable library-like modules in `Core/`, `Craft/`, and `UI/`, with thin feature/config files that compose those modules. If a second feature needs similar logic, extract a shared helper instead of copy-pasting.

## Load Order

This addon does not use Lua `require`; `smart_rez.toc` controls runtime order.

- Update `smart_rez.toc` whenever runtime files move or are added.
- Load shared helpers/components before feature files that consume them.
- Do not add annotation-only files, `DevTools/` probes, or `Legacy/` reference files to the TOC.
- Use folder-qualified paths in XML files when files move.
- Keep `embeds.xml`, vendored `Libs/`, and Lua `LibStub(...)` usage aligned.

## Secure And Profession Rules

Retail secure buttons and profession access are fragile. Preserve these patterns:

- Do not call `C_TradeSkillUI.OpenTradeSkill(...)` from passive refresh paths, cache rebuilds, config setters, or inventory scans.
- Protected profession opening must happen from a user click path.
- Recipe craft and salvage selections have `requireProfessionOpen` flags. Default to `true`, but allow verified recipes to skip opening/selecting the profession UI and call the craft API directly.
- For remote storage/profession backend access, use `Core/professionProxy.lua`:
  - `SmartRez:IsProfessionProxyReady(professionID)`
  - `SmartRez:OpenProfessionProxy(professionID)`
- Treat "needs profession backend priming" as a valid state, not as "no work exists".
- Warbank support exists but is not the safest default; prefer player bags unless explicitly testing warbank behavior.

## Secure Button Timing

- Keep `RegisterForClicks("AnyUp", "AnyDown")` when a feature must respect `ActionButtonUseKeyDown`.
- If both click phases are registered, gate work with the active phase.
- Preserve event-driven craft/disenchant locks. Do not replace stable state machines with arbitrary repeated timers.
- Recipe craft and salvage should share craft-controller primitives from `Core/craftCore.lua` where possible.
- Gold Printer priority interrupts must stay click-driven. They may use `/stopcasting` plus craft-controller unlocks for active craft-in-progress locks, but must not bypass bag-space waits or passive profession-opening gates.

## Inventory Sources

`inventorySources` is shared by craft, salvage, and disenchant workflows.

- Prefer shared scan helpers in `Core/core.lua`:
  - `GetCraftingItemSourceContainerIDs()`
  - `ForEachCraftingItemSourceSlot(...)`
  - `ForEachPlayerBagSlot(...)`
- Do not "fix" timing bugs by silently making scans player-bag-only; that can break warbank behavior.
- Separate readiness/access logic from target selection logic.
- AH Sniper bait and AH Selling can each reserve a minimum player-bag count per item. Non-bait consumers should use spendable-count helpers such as `GetCraftingSpendableItemCount(...)` and `GetSpendableStackCount(...)`; bait posting intentionally ignores these reserves.

## Integrations

- Auctionator is expected for AH workflows, but still nil-check optional frames/mixins at load time.
- TSM is optional; never assume `TSM_API` exists.
- Keep integration-specific frame/API details inside `Integrations/` or clearly named AH helper modules.
- Add optional addon globals to `Annotations/addon-globals.lua`.

## Debugging

- Use the shared debug setting in `Core/core.lua`:
  - `SmartRez:GetDebugEnabled()`
  - `SmartRez:SetDebugEnabled(value)`
- Prefer high-signal feature-prefixed logs.
- Avoid noisy per-refresh/per-frame logs unless actively narrowing a bug.

## Research And Verification

Build context in this order:

1. this addon's existing code and closest `AGENTS.md`
2. parent `AGENTS.md` files up to this root
3. nearby addons in the parent `AddOns` folder
4. vendored libraries in `Libs/`
5. current Retail/Midnight documentation
6. targeted live-game `/dump`, `/eventtrace`, or `/run print(...)` checks from the user

Do not guess modern WoW API fields, event payloads, or return values when a live dump can verify them. Treat user-provided live-game dumps as the strongest source of truth.

## Known API Findings

Salvage:

- Use `recipeSchematic.quantityMin` / `quantityMax` for salvage target stack requirements.
- Use `C_TradeSkillUI.GetSalvagableItemIDs(recipeID)` for salvage target candidates.
- Use `recipeSchematic.reagentSlotSchematics[*].reagents` for per-slot reagent choices.
- Keep salvage target filtering separate from reagent-slot filtering.
- `C_TradeSkillUI.CraftSalvage(...)` can take target `ItemLocation` plus extra reagent tables.

Crafting quality:

- Do not use normal item rarity for profession reagent quality.
- Use `C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)`.
- If icon mapping is unclear, ask for live dumps rather than inventing conversions.

## Programming Guide

Good changes usually:

- reduce duplication by promoting shared behavior into `Core/`, `Craft/`, or `UI/`
- keep config/registration files simple and declarative
- split UI, persistence, integration, and execution concerns
- preserve secure-button timing and profession-proxy flows
- use modern Retail APIs and reduce unnecessary `_G`
- add precise annotations instead of suppressing diagnostics
- document new stable seams, workflows, commands, APIs, state, config, and ownership boundaries before finishing

Avoid:

- new root-level runtime Lua files
- broad rewrites of unrelated code
- deprecated APIs when a current `C_` API exists
- Classic-safe fallbacks unless requested
- mixing UI, persistence, and execution in one new file unless the feature is tiny
- opening protected profession UI from passive refresh paths
- checking in generated binaries, caches, local scratch files, or temporary artifacts

## Verification

Before finishing a change:

- run the most relevant checks available for the touched area
- inspect `smart_rez.toc` when runtime files move or are added
- search for stale references after renames or API moves
- document checks that could not be run
- do not claim success for checks that were not run

For documentation-only changes, verify the `AGENTS.md` index and Markdown structure.
