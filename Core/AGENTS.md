# Core/AGENTS.md

## Scope

`Core/` owns addon-wide state and shared runtime primitives. Code here should be reusable by features without knowing about feature-specific UI.

## Owned Files

- `core.lua`: root addon object, saved state helpers, shared debug setting, inventory source helpers, and general utilities.
- `craftCore.lua`: event-driven craft lock/controller primitives shared by recipe craft and salvage flows.
- `professionProxy.lua`: protected profession backend priming helpers.
- `playerBagRestack.lua`: player-bag restack helpers.
- `ahShared.lua`: shared Auction House helpers used by AH-facing features/UI.
- `overrideBindings.lua`: binding override runtime behavior.
- `slashCommands.lua`: `/sr` command registration and command routing.

## Contracts

- Keep cross-feature behavior here only when it is genuinely shared.
- Preserve modern Retail API usage and avoid Classic compatibility shims.
- Do not open professions from passive refresh, scans, cache rebuilds, config setters, or other non-click paths.
- Keep remote profession/backend access behind `professionProxy.lua`.
- Keep inventory scan helpers source-aware; do not silently collapse shared scans to player bags.
- Keep AH item reserves centralized in Core helpers. Workflows that consume items should use `GetCraftingSpendableItemCount(...)` or `GetSpendableStackCount(...)` so configured AH Sniper bait and AH Selling keep-in-bags counts are preserved.
- AH Selling saved state includes the unified AH Buy/Sell scheduler cadence. Keep the default in `core.lua` aligned with `Features/ahSelling.lua` normalization.
- Craft action controllers may allow a Gold Printer priority interrupt only for an active craft-in-progress lock. Do not bypass bag-space waits or passive profession/opening gates.
- `goldPrinterWorkGeneration` is the shared invalidation counter for Gold Printer's per-step no-work memo. Bump it when core inventory/profession state changes or when feature/config code changes Gold Printer target availability.
- Keep slash commands thin. Route to existing feature/UI entrypoints instead of embedding feature logic.
- `/sr buywarn` and aliases route to the AH Sniper manual bait-warning refresh; keep AH scan logic in `Features/ahSniper.lua`.
- When adding shared state, document persistence scope and SavedVariables impact in the root doc if it changes addon-wide behavior.

## Child Documentation

No child `AGENTS.md` files exist yet. Add one only if a subdirectory or extracted subsystem grows under `Core/`.

## Doc Updates

Update this file when shared helpers, saved-state contracts, slash commands, inventory source behavior, profession proxy behavior, craft controller primitives, or binding runtime behavior change.
