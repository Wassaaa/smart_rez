# AGENTS.md

## Project Purpose

`smart_rez` is a Retail-only World of Warcraft addon focused on automation helpers, bindable actions, profession workflows, salvage/craft logic, low-mode utilities, and integrations with external addons such as Auctionator and TradeSkillMaster.

This project targets modern Retail only.

- Treat `World of Warcraft: Midnight` as the active expansion baseline.
- Do not preserve Classic, Cataclysm Classic, or other legacy compatibility unless explicitly requested.
- Prefer current Retail APIs and patterns over old compatibility shims.

## Core Expectations

Future agents working in this repo should optimize for:

- No LuaLS squiggles for code we own.
- Proper typing and annotations where LuaLS inference is weak.
- Small, reusable, professional modules with clear responsibility boundaries.
- Minimal churn to unrelated files.
- Retail-first WoW API usage.

## API Rules

### Prefer modern Retail APIs

Use current namespaced APIs when available.

Examples:

- `C_Item.GetItemInfo(...)` instead of `GetItemInfo(...)`
- `C_TradeSkillUI.OpenTradeSkill(...)` instead of `_G["C_TradeSkillUI"]["OpenTradeSkill"](...)`
- `C_Container.GetContainerItemInfo(...)` instead of old bag APIs
- `Settings.OpenToCategory(...)` instead of `InterfaceOptionsFrame_OpenToCategory(...)`

### Avoid unnecessary `_G`

Do not use `_G[...]` for normal Blizzard globals or stable API tables unless there is a real reason.

Prefer:

- `CreateFrame`
- `UIParent`
- `ProfessionsFrame`
- `C_Timer.After`
- `EnumerateFrames`

Keep `_G` only for cases like:

- the addon root object: `_G.SmartRez`
- dynamic global lookups: `_G[action.buttonName]`
- Blizzard binding label globals that must be string-indexed
- optional third-party addon globals when first localizing them

## Secure Actions And Profession Access

Retail secure-button behavior and profession-window access are easy places to regress this addon. Follow these rules:

- Do not call `C_TradeSkillUI.OpenTradeSkill(...)` from passive refresh paths such as inventory scans, cache rebuilds, `Refresh...()` helpers, or config setters.
- Passive refresh code may check readiness, but opening protected UI must happen only from an actual user click path.
- When remote crafting sources such as warbank depend on the profession backend being open, use the profession-proxy helpers in `professionProxy.lua`:
  - `SmartRez:IsProfessionProxyReady(professionID)`
  - `SmartRez:OpenProfessionProxy(professionID)`
- Prefer the existing profession proxy flow over direct one-off profession-opening logic in feature modules.
- If remote storage cannot be scanned until the profession backend is open, treat that as a valid "priming" state rather than "no work exists".
- Warbank crafting/salvage support exists, but it is not stable enough to assume as the default source. Prefer player bags by default unless the user is explicitly testing warbank behavior.

### Disenchant-specific secure pattern

`disenchant.lua` now follows a stricter Retail-safe pattern and future edits should preserve it unless explicitly replacing it end-to-end:

- Keep the bindable button macro-based.
- Use hidden secure helper buttons for spell targeting / verification rather than rebuilding unrelated logic elsewhere.
- Keep the spam-safety state machine event-driven:
  - `UNIT_SPELLCAST_START`
  - `UNIT_SPELLCAST_SUCCEEDED`
  - `UNIT_SPELLCAST_STOP`
  - `ITEM_LOCKED`
  - `ITEM_UNLOCKED`
  - `ITEM_PUSH`
  - `LOOT_READY`
  - `LOOT_OPENED`
  - `LOOT_CLOSED`
- Do not re-enable disenchant during the cast-success / loot handoff window.
- Preserve the current fast-loot flow if touching disenchant completion timing.

### Click phase handling

Some secure buttons in this addon intentionally register both key-down and key-up phases.

- It is acceptable to keep `RegisterForClicks("AnyUp", "AnyDown")` when the feature needs to respect the user's `ActionButtonUseKeyDown` setting.
- If both phases are registered, gate addon logic so work only happens on the active phase instead of both.
- Do not "fix" duplicate logs or duplicate macro prep by removing one phase unless the feature truly does not need to respect both click models.

## Inventory Source Behavior

`inventorySources` is shared infrastructure for crafting, salvage, and disenchant workflows.

- Prefer scanning through the shared helpers in `core.lua`:
  - `GetCraftingItemSourceContainerIDs()`
  - `ForEachCraftingItemSourceSlot(...)`
  - `ForEachPlayerBagSlot(...)`
- Be careful when changing source scans for disenchant. A player-bag-only scan may appear to fix timing bugs while silently breaking warbank behavior.
- If a workflow needs different behavior for local vs remote sources, separate readiness / access logic from target selection logic rather than forking the whole workflow.

## Debug Output

Debug logging should follow a shared addon pattern rather than ad hoc file-local toggles.

- Use the shared debug setting in `core.lua`:
  - `SmartRez:GetDebugEnabled()`
  - `SmartRez:SetDebugEnabled(value)`
- New module debug prints should stay lightweight and high-signal.
- Prefer feature-prefixed messages such as `SmartRez DE: ...`.
- Avoid noisy per-refresh or per-frame spam unless actively narrowing a bug and explicitly requested.

## Typing And LuaLS

### Goal

All code we own should be clean under LuaLS. If LuaLS cannot infer a valid pattern, add annotations instead of leaving noise behind.

### Annotation locations

Tooling-only LuaLS annotations live in:

- [Annotations/acegui.lua](/e:/World%20of%20Warcraft/_retail_/Interface/AddOns/smart_rez/Annotations/acegui.lua)
- [Annotations/addon-globals.lua](/e:/World%20of%20Warcraft/_retail_/Interface/AddOns/smart_rez/Annotations/addon-globals.lua)

Rules:

- Do not add annotation-only files to `smart_rez.toc`.
- Keep annotation files focused and small.
- Extend existing annotations before adding duplicate ad hoc casts everywhere.

### When to annotate

Add or refine annotations when:

- AceGUI widget factory returns are too dynamic for LuaLS
- optional addon globals like `TSM_API` or Auctionator globals need `_G` field typing
- local custom window objects add fields such as `tabs`, `values`, `enableCheck`, or cached UI handles

### Preferred typing style

- Use `---@class` for shared structured objects
- Use `---@field` for addon-managed fields
- Use `---@type` on locals returned from dynamic factories
- Prefer typing the factory/shim once instead of scattering ignores
- Do not suppress warnings if a real annotation can explain the shape

## Research Workflow

When implementing or refactoring features, build context from the best available sources in this order:

1. this addon's existing code
2. nearby addons in the parent AddOns directory
3. vendored library source in `Libs/`
4. current web documentation for Retail/Midnight APIs and library behavior

### Live game verification

This project has a better-than-normal source of truth available during development: the user's live Retail client.

- Do not guess WoW API globals, event names, event payloads, or return-value meanings from memory when they can be verified from the live game.
- If a value is uncertain, ask the user for `/dump`, `/eventtrace`, or a tiny `/run print(...)` check instead of inventing a likely answer.
- Treat live game dumps from the user as more authoritative than recalled knowledge.
- Be explicit about what was verified versus what is still an inference.
- Do not imply that Codex personally tested behavior in-game; only the user can run those live checks.

### Local addon references

This addon is usually developed inside the main WoW `AddOns` folder, so the directory one level up is often a strong reference source for real working implementations.

Use that nearby addon ecosystem as a practical reference when:

- looking for modern UI patterns
- checking how another addon handles a Blizzard system
- finding examples of Auctionator, TSM, Ace3, or profession UI integrations
- comparing module layout or event-handling patterns

Search those files intelligently and narrowly.

Prefer:

- targeted text search for API names, mixins, events, XML templates, or frame names
- reading only the most relevant files instead of broad dumping
- borrowing patterns, not blindly copying code

## File Organization

Keep runtime files small and grouped by feature.

Current rough organization:

- `core.lua`: addon root, shared state, profession state tracking, core helpers
- `overrideBindings.lua`: settings registration, popup window, keybind flow
- `automationConfigUi.lua`: main automation setup UI
- `craftRecipeCore.lua`: profession crafting action execution
- `craftSalvageCore.lua`: salvage target selection and salvage execution
- `craftSalvageConfig.lua`: salvage config storage, recipe selection, whitelist logic
- `recipeCrafts.lua`, `salvageActions.lua`: feature registrations/data wiring
- `goldPrinter.lua`: phase-based dispatcher
- `tsmLabelClick.lua`: TSM label button discovery/click integration
- `snipeAuctionator.lua`: Auctionator commodity integration
- `lowmode.lua`: low graphics/UI mode helper
- `disenchant.lua`: disenchant targeting/action logic

### Preferred module boundaries

When adding or refactoring features:

- split by feature or subsystem, not by arbitrary file size alone
- separate config/state logic from execution logic
- separate UI building from business logic
- keep third-party addon integrations isolated to their own files
- avoid giant mixed-purpose files

If a file starts holding multiple unrelated responsibilities, split it.

## Third-Party Addon Integrations

### Auctionator

Auctionator is a dependency.

- treat Auctionator globals as optional at load time
- localize them once if needed
- nil-check frames/mixins before use
- annotate optional globals through `Annotations/addon-globals.lua`

### TradeSkillMaster

TSM is optional.

- never assume TSM is loaded
- guard `TSM_API` usage
- prefer graceful early returns and user-facing messages over hard failures
- keep TSM-specific scanning and callbacks inside `tsmLabelClick.lua` or a dedicated future TSM module

## AceGUI Guidance

AceGUI is used for custom popup/setup UI.

- keep AceGUI usage typed
- prefer reusable helper functions for repeated row/group patterns
- use `SetLayout` intentionally
- use `AddChild` on proper container widgets only
- prefer widget-level APIs like `:IsShown()` over poking `widget.frame` unless needed

If LuaLS struggles with AceGUI factory returns, improve `Annotations/acegui.lua` first.

## Editing Guidelines

- Preserve behavior unless explicitly changing behavior.
- Make the smallest clean change that solves the issue.
- Do not add runtime-only compatibility branches for old WoW versions unless requested.
- Do not reintroduce deprecated APIs when a current Retail equivalent exists.
- Avoid broad rewrites of files with unrelated user changes.

## TOC And Load Order

When adding runtime Lua modules:

- update `smart_rez.toc` intentionally
- keep load order valid for dependencies between files
- do not add annotation-only files to the TOC

## Web Verification Rules

Do not assume recalled knowledge is current for modern WoW addon APIs.

When local code is not enough, do not guess WoW API field meanings or value mappings from memory.

- Ask the user to run targeted `/dump` commands for the exact live API values instead of assuming.
- Prefer confirming real live-returned fields over adding fallback logic based on recollection.
- If a value meaning is ambiguous, stop and verify with user-provided dumps before hardcoding behavior.
- Treat modern profession and crafting-quality APIs as especially dump-first.

If local source and vendored library code are not enough:

- web search for the current Retail implementation
- prefer official or primary sources first
- verify against the most modern live version, currently `World of Warcraft: Midnight`
- treat older forum posts, TWW-era snippets, and pre-Midnight advice as suspect until confirmed

Use web verification especially for:

- Blizzard API changes or deprecations
- profession UI behavior
- Settings UI behavior
- secure button behavior
- Auction House and item APIs
- library usage when repo-local docs are weak

Midnight changed parts of the addon API surface. Many older patterns still work, but future agents should verify instead of assuming.

## Salvage API Findings

Recent live testing in this repo established a few salvage-specific rules that future edits should preserve unless the APIs change again:

- Do not assume salvage target stack size comes from `reagentSlotSchematics`.
- For salvage recipes, prefer `recipeSchematic.quantityMin` / `quantityMax` for the salvage target stack requirement.
- Use `C_TradeSkillUI.GetSalvagableItemIDs(recipeID)` for the salvage target candidate pool.
- Use `recipeSchematic.reagentSlotSchematics[*].reagents` for per-slot allowed reagent item choices.
- Treat salvage target filtering and reagent-slot filtering as separate concepts in config and UI.
- `C_TradeSkillUI.CraftSalvage(...)` can take the salvage target item location plus an additional reagent table for extra required slots.
- When a salvage recipe has extra required reagent slots, limit casts by both the salvage target stack and those reagent quantities.

### Crafting quality findings

- Do not use normal item rarity for profession reagent quality UI.
- Use `C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)` for reagent quality.
- Older three-tier reagents report `1/2/3` as bronze/silver/gold.
- Midnight two-tier reagents report `1/2`, but should display using the Midnight profession-quality icon family rather than the legacy one.
- If the exact icon mapping is unclear, ask the user for dumps instead of inventing a conversion.

## Preferred Refactor Direction

Over time, this addon should move toward:

- clearer separation between core state, action execution, config persistence, and UI
- thinner integration adapters for Auctionator/TSM
- fewer global assumptions
- stronger LuaLS annotations instead of diagnostic suppression
- reusable helpers instead of repeated inline UI/build logic

## What Good Changes Look Like

Good changes in this repo usually:

- replace old API usage with a current Retail API
- reduce unnecessary `_G` access
- add precise annotations instead of ignoring diagnostics
- split large behavior into smaller helpers or modules
- keep integration-specific logic isolated
- preserve working secure-button timing and profession-proxy flows when touching automation features

## What To Avoid

- Classic-safe fallbacks unless explicitly requested
- adding annotation files to the runtime TOC
- using deprecated globals when a `C_` API exists
- suppressing LuaLS warnings without first attempting to type the code properly
- mixing UI, persistence, and action execution in a single new file unless the feature is truly tiny
- opening protected profession UI from passive refresh or inventory change handlers
- assuming "no scanned target" means "no work exists" when remote inventory sources may still need backend access
- replacing a stable event-driven state machine with ad hoc timing delays or broad repeated checks
