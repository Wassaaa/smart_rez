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
- `ahSelling.lua`, `ahSniper.lua`, and `ahScheduler.lua`: Auction House selling/sniping workflows and the unified AH buy/sell scheduler button.
- `menuProbe.lua`: runtime probe/feature helper. Keep probe behavior intentional and low-noise.

## Contracts

- Keep feature files thin when possible: orchestration, state transitions, and registrations belong here; reusable helpers belong in `Core/`, `Craft/`, or `UI/`.
- Preserve event-driven locks for craft, salvage, and disenchant flows.
- Do not open protected profession UI from passive feature refreshes or config changes.
- Prefer player-bag behavior as the safe default, but do not break warbank/source-aware flows by narrowing shared scans.
- Keep feature debug logs high-signal and prefixed.
- For AH features, nil-check optional Auctionator/TSM surfaces and keep integration-specific details isolated.
- AH Sniper owns bait buy/post configuration, and AH Selling owns sell stock configuration. Both may define per-item keep-in-bags reserves; other item-consuming features should respect those reserves through Core spendable-count helpers. AH Sniper bait posting itself intentionally ignores keep-in-bags reserves.
- AH Scheduler owns the unified AH Buy/Sell bindable action. It must only start AH actions through AH Sniper/AH Selling status-returning APIs, count only successful throttle-consuming buy/bait calls toward the sell cadence, and avoid starting a new AH action while buy, bait, sell scan, or sell post work is pending.
- Gold Printer routine steps may own per-step disenchant or salvage whitelist context storage keyed by routine and step index. Step move, remove, or type-change operations must remap or clear that context storage in the same mutation so target lists stay attached to the logical step.
- Gold Printer priority steps include timed priority and buff priority. Buff priority is a generic condition wrapper for any Gold Printer step type and can key off a tracked player buff being missing/low or present. Priority dispatch may prepend `/stopcasting` and allow the target craft controller to unlock an active craft-in-progress lock so the priority step can run; keep this click-driven and do not turn it into a passive timer.

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

Update this file when feature ownership changes, a workflow gains new state/config/API contracts, secure timing changes, AH behavior changes, item reserve behavior changes, or feature code graduates into shared modules.
