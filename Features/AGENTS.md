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
- Bag Value has a default TSM price source plus optional per-item price source overrides stored under its item config. Blank per-item sources inherit the default; nonblank per-item sources should affect only that item in value snapshots.
- For AH features, nil-check optional Auctionator/TSM surfaces and keep integration-specific details isolated.
- AH Sniper owns bait buy/post configuration, and AH Selling owns sell stock configuration. Both may define per-item keep-in-bags reserves; other item-consuming features should respect those reserves through Core spendable-count helpers. AH Sniper bait posting itself intentionally ignores keep-in-bags reserves.
- AH Sniper normal buys should stay quote-first through `StartCommoditiesPurchase(...)` and should not send commodity searches before the initial buy. Post-buy bulk opportunity scans are allowed only after a successful normal purchase and must still validate the live quoted total before confirming a larger quantity. Bulk scan/buy follow-up is time-sensitive and should not grant sell-cadence credit.
- AH Sniper may manually refresh Auctionator-style commodity low-price warning thresholds for configured buy items. This is a user-requested scan flow only, must run one configured item at a time behind AH throttle readiness, should use Auctionator's `PriceWarningThreshold(...)` helper when available, and must not run in parallel with buy, bait, bulk, or active AH Selling work.
- AH Scheduler owns the unified AH Buy/Sell bindable action. It must only start AH actions through AH Sniper/AH Selling status-returning APIs, count bait posts and completed failed normal snipe buys toward the sell cadence, never count successful normal or bulk buys toward selling, prioritize active AH Sniper bulk follow-up before selling, and avoid starting a new AH action while buy, bait, sell scan, or sell post work is pending.
- AH Sniper successful normal buys start a buy-first chain: the next scheduler action should process the bulk/top-stack follow-up, then the next normal fixed-stack buy must run before any sell or bait action. Bait may resume only after that fixed-stack buy attempt has been made.
- Gold Printer routine steps may own per-step disenchant or salvage whitelist context storage keyed by routine and step index. Step move, remove, or type-change operations must remap or clear that context storage in the same mutation so target lists stay attached to the logical step.
- Gold Printer salvage context keys use the unprefixed form from `GetGoldPrinterRoutineStepCraftSalvageContextKey(...)`. Preserve migration from the older `context:goldprinter:...` default key when touching default salvage whitelist initialization.
- Gold Printer priority steps include timed priority and buff priority. Buff priority is a generic condition wrapper for any Gold Printer step type and can key off a tracked player buff being missing/low or present. Priority dispatch may prepend `/stopcasting` and allow the target craft controller to unlock an active craft-in-progress lock so the priority step can run; keep this click-driven and do not turn it into a passive timer.
- Gold Printer priority craft interrupts are single-dispatch for a given priority step. Once the priority craft has been dispatched, spammed Gold Printer clicks must respect the craft controller lock until that priority craft finishes instead of repeatedly sending `/stopcasting`.
- Gold Printer may memoize per-step "no work" results for the current work generation to keep repeated empty bind presses cheap. Invalidate that generation when inventory, profession state, step config, whitelists, or reagent/salvage choices change. Internal step skipping during an empty scan should not force full setup UI rebuilds.

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
