# AGENTS.md

## Project

`smart_rez` is a Retail-only World of Warcraft addon for automation helpers, profession workflows, salvage/craft/disenchant logic, low-mode utilities, and integrations with Auctionator and TradeSkillMaster.

- Target modern Retail only. Treat `World of Warcraft: Midnight` as the active baseline.
- Prefer current namespaced APIs such as `C_Item.*`, `C_Container.*`, `C_TradeSkillUI.*`, and `Settings.*`.
- Do not preserve Classic or legacy compatibility unless explicitly requested.
- Keep owned code LuaLS-clean with annotations instead of warning suppression.

## Architecture

Use a layered, reusable-module style:

- `Core/`: addon root, shared state, inventory/profession helpers, craft lock/controller helpers, profession proxy, bag restack.
- `Craft/`: reusable recipe-craft and salvage systems, craft/salvage config storage, craft action registrations.
- `Features/`: user-facing workflows such as Gold Printer, bag value, disenchant, low mode, warbank grab, and probes.
- `UI/`: AceConfig/AceGUI windows, reusable UI components, feature setup tabs.
- `Integrations/`: isolated Auctionator/TSM adapters.
- `DevTools/`: local WoWLua probes and development-only scripts; do not load these from the TOC unless explicitly promoted to runtime code.

Prefer reusable library-like modules in `Core/`, `Craft/`, and `UI/`, with thin feature/config files that compose those modules. If a second feature needs similar logic, extract a shared helper instead of copy-pasting.

## Load Order

This addon does not use Lua `require`; `smart_rez.toc` controls runtime order.

- Update `smart_rez.toc` whenever runtime files move or are added.
- Load shared helpers/components before feature files that consume them.
- Do not add annotation-only files or `DevTools/` probes to the TOC.
- Use folder-qualified paths in XML files when files move.

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
- If both click phases are registered, gate work with the active phase instead of removing a phase.
- Preserve event-driven craft/disenchant locks. Do not replace stable state machines with arbitrary repeated timers.
- Recipe craft and salvage should share craft-controller primitives from `Core/craftCore.lua` where possible.

## Disenchant

`Features/disenchant.lua` uses a strict Retail-safe flow:

- Keep the bindable button macro-based.
- Use hidden secure helper buttons for spell targeting/verification.
- Player-bag disenchant does not need the profession window open.
- Warbank/remote-source disenchant may need the Enchanting backend primed; keep that automatic through the profession proxy instead of adding a manual "require profession window" toggle.
- Preserve the event-driven lock around `UNIT_SPELLCAST_*`, item lock/unlock, item push, and loot events.
- Do not re-enable disenchant during the cast-success to loot handoff.
- Preserve fast-loot behavior unless replacing the whole flow deliberately.

## Inventory Sources

`inventorySources` is shared by craft, salvage, and disenchant workflows.

- Prefer shared scan helpers in `Core/core.lua`:
  - `GetCraftingItemSourceContainerIDs()`
  - `ForEachCraftingItemSourceSlot(...)`
  - `ForEachPlayerBagSlot(...)`
- Do not "fix" timing bugs by silently making scans player-bag-only; that can break warbank behavior.
- Separate readiness/access logic from target selection logic.

## UI

AceGUI custom UI lives in `UI/`.

- Reuse `UI/uiComponents.lua` for cards, rows, icon pickers, and repeated controls.
- Keep feature tab files thin and composition/config oriented.
- Improve `Annotations/acegui.lua` when AceGUI types are unclear.
- Do not add annotation files to the TOC.
- AceGUI widgets are pooled. Any custom frame regions, textures, callbacks, or ticker closures attached to widgets must clean up on `OnRelease` or otherwise stop updating released widgets.
- Use AceGUI status tables via shared helpers for movable window positions; do not hand-roll separate position systems unless needed.
- Bag Value's timer/rate session is display-scoped: it starts while `/sr value` or the Bag Value tab is visible and resets when all Bag Value displays close. Window position is saved, timer state is not.

## Integrations

- Auctionator is a dependency, but still nil-check optional frames/mixins at load time.
- TSM is optional; never assume `TSM_API` exists.
- Keep integration-specific frame/API details inside `Integrations/`.
- Add optional addon globals to `Annotations/addon-globals.lua`.

## Debugging

- Use the shared debug setting in `Core/core.lua`:
  - `SmartRez:GetDebugEnabled()`
  - `SmartRez:SetDebugEnabled(value)`
- Prefer high-signal feature-prefixed logs.
- Avoid noisy per-refresh/per-frame logs unless actively narrowing a bug.

## Research And Verification

Build context in this order:

1. this addon's existing code
2. nearby addons in the parent `AddOns` folder
3. vendored libraries in `Libs/`
4. current Retail/Midnight documentation
5. targeted live-game `/dump`, `/eventtrace`, or `/run print(...)` checks from the user

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

## Good Changes

Good changes usually:

- reduce duplication by promoting shared behavior into `Core/`, `Craft/`, or `UI/`
- keep config/registration files simple and declarative
- split UI, persistence, integration, and execution concerns
- preserve secure-button timing and profession-proxy flows
- use modern Retail APIs and reduce unnecessary `_G`
- add precise annotations instead of suppressing diagnostics

Avoid:

- new root-level runtime Lua files
- broad rewrites of unrelated code
- deprecated APIs when a current `C_` API exists
- Classic-safe fallbacks unless requested
- mixing UI, persistence, and execution in one new file unless the feature is tiny
- opening protected profession UI from passive refresh paths
