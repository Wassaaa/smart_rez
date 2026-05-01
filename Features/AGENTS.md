# Features/AGENTS.md

## Scope

`Features/` owns user-facing workflows. Feature files should compose shared systems from `Core/`, `Craft/`, `UI/`, and `Integrations/` rather than becoming large mixed UI/persistence/execution modules.

## Owned Files

- `bagValue.lua`: bag value scanning/session behavior.
- `disenchant.lua`: Retail-safe disenchant workflow.
- `goldPrinter.lua` and `goldPrinterConfig.lua`: gold printer workflow and configuration.
- `recipeCrafts.lua`: recipe craft registrations.
- `warbankGrab.lua`: warbank grab workflow.
- `lowmode.lua`: low-mode utilities and persisted low-mode behavior.
- `ahSelling.lua` and `ahSniper.lua`: Auction House selling/sniping workflows.
- `menuProbe.lua`: runtime probe/feature helper. Keep probe behavior intentional and low-noise.

## Contracts

- Keep feature files thin when possible: orchestration, state transitions, and registrations belong here; reusable helpers belong in `Core/`, `Craft/`, or `UI/`.
- Preserve event-driven locks for craft, salvage, and disenchant flows.
- Do not open protected profession UI from passive feature refreshes or config changes.
- Prefer player-bag behavior as the safe default, but do not break warbank/source-aware flows by narrowing shared scans.
- Keep feature debug logs high-signal and prefixed.
- For AH features, nil-check optional Auctionator/TSM surfaces and keep integration-specific details isolated.

## Disenchant Contract

`disenchant.lua` uses a strict Retail-safe flow:

- Keep the bindable button macro-based.
- Use hidden secure helper buttons for spell targeting/verification.
- Player-bag disenchant does not need the profession window open.
- Warbank/remote-source disenchant may need the Enchanting backend primed through the profession proxy.
- Preserve the event-driven lock around `UNIT_SPELLCAST_*`, item lock/unlock, item push, and loot events.
- Do not re-enable disenchant during the cast-success to loot handoff.
- Preserve fast-loot behavior unless replacing the whole flow deliberately.

## Child Documentation

No child `AGENTS.md` files exist yet. Add one when a feature family gains multiple files or local rules that should not live in this broad feature contract.

## Doc Updates

Update this file when feature ownership changes, a workflow gains new state/config/API contracts, secure timing changes, AH behavior changes, or feature code graduates into shared modules.
