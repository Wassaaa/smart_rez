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
- Treat "needs profession backend priming" as a valid state that the UI/feature can surface or resolve through the profession proxy.
- Do not add UI construction here. UI belongs in `UI/`; user workflows belong in `Features/`.

## Child Documentation

No child `AGENTS.md` files exist yet. Add one if craft and salvage split into stable subdirectories.

## Doc Updates

Update this file when craft/salvage execution rules, config persistence, action registration, salvage API findings, or profession-open assumptions change.
