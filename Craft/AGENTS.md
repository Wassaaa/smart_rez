# Craft/AGENTS.md

## Scope

`Craft/` owns reusable crafting and salvage systems. Feature files should register or compose actions here instead of duplicating recipe/salvage execution logic.

## Owned Files

- `craftRecipeCore.lua`: reusable recipe crafting execution logic.
- `craftSalvageCore.lua`: reusable salvage execution logic and salvage target handling.
- `craftSalvageConfig.lua`: salvage/craft configuration storage and accessors.
- `salvageActions.lua`: salvage action registration and wiring.

## Contracts

- Default recipe craft and salvage selections to `requireProfessionOpen = true` unless the recipe has been verified safe for direct API calls.
- Keep salvage target filtering separate from reagent-slot filtering.
- Use `recipeSchematic.quantityMin` / `quantityMax` for salvage target stack requirements.
- Use `C_TradeSkillUI.GetSalvagableItemIDs(recipeID)` for salvage candidates.
- Use `recipeSchematic.reagentSlotSchematics[*].reagents` for per-slot reagent choices.
- Share craft-controller primitives from `Core/craftCore.lua` where possible.
- Recipe craft and salvage availability must respect shared AH item reserve helpers from `Core/`; do not use raw item counts for consumable reagents or salvage targets when choosing how many casts are available.
- Salvage planning must also respect selection-local target and reagent item minimums when present. Gold Printer uses these as per-step "keep at least this many" thresholds for selected target and reagent items.
- Salvage reagent plans must account for every required reagent slot before dispatch. Debug logs should identify the target-cast count, final reagent-capped casts, and any failing reagent slot by candidate count, allowed count, spendable count, and failure reason.
- Active per-feature salvage selections may be refreshed from the current recipe schematic once the user-click craft path has opened/selected the recipe, so saved step data does not silently miss newly discovered required reagent slots.
- Salvage whitelist mutations can affect Gold Printer step availability. Keep those mutations aligned with Gold Printer work-generation invalidation so repeated empty Gold Printer presses do not reuse stale no-work results.
- Treat "needs profession backend priming" as a valid state that the UI/feature can surface or resolve through the profession proxy.
- Do not add UI construction here. UI belongs in `UI/`; user workflows belong in `Features/`.

## Child Documentation

No child `AGENTS.md` files exist yet. Add one if craft and salvage split into stable subdirectories.

## Doc Updates

Update this file when craft/salvage execution rules, config persistence, action registration, salvage API findings, or profession-open assumptions change.
