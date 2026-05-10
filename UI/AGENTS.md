# UI/AGENTS.md

## Scope

`UI/` owns AceConfig/AceGUI windows, reusable UI components, and feature setup tabs. UI files should compose feature and config APIs rather than own core execution behavior.

## Owned Files

- `uiComponents.lua`: shared cards, rows, icon pickers, layout helpers, and repeated controls.
- `automationConfigUi.lua`: automation setup/config surface.
- `bagValueConfigUi.lua`: bag value tab/window UI.
- `disenchantConfigUi.lua`: disenchant setup UI.
- `goldPrinterConfigUi.lua`: gold printer setup UI.
- `salvageConfigUi.lua`: salvage setup UI.
- `ahSellingUi.lua` and `ahSniperUi.lua`: Auction House feature UI.
- `overrideBindingOptions.lua` and `overrideBindingPopup.lua`: binding configuration UI.

## Contracts

- Reuse `uiComponents.lua` for repeated controls before adding local one-off builders.
- Keep feature tab files composition/config oriented.
- Do not put execution state machines in UI files.
- AceGUI widgets are pooled. Any custom frame regions, textures, callbacks, or ticker closures attached to widgets must clean up on `OnRelease` or otherwise stop updating released widgets.
- Use AceGUI status tables via shared helpers for movable window positions.
- Bag Value's timer/rate session is display-scoped: it starts while `/sr value` or the Bag Value tab is visible and resets when all Bag Value displays close. Window position is saved, timer state is not.
- Bag Value UI owns the compact per-selected-item price-source rows. Leave price calculation and default-vs-override resolution in `Features/bagValue.lua`.
- AH Sniper and AH Selling UI own per-item keep-in-bags controls that feed shared reserve behavior in Core. AH Selling UI also owns the unified AH Buy/Sell scheduler cadence setting. Keep reserve enforcement and scheduler execution out of UI files.
- AH Sniper UI may display cached Auctionator-style bait warning thresholds and provide a manual refresh control, but the scan/throttle state belongs in `Features/ahSniper.lua`.
- Gold Printer UI exposes priority settings, including generic step buff spell IDs, buff condition direction, and refresh thresholds. UI should only persist settings through `Features/goldPrinterConfig.lua`; priority execution belongs in `Features/goldPrinter.lua`.
- Improve `Annotations/acegui.lua` when AceGUI types are unclear.

## Child Documentation

No child `AGENTS.md` files exist yet. Add one if a UI feature grows into a stable component family or custom window subsystem.

## Doc Updates

Update this file when shared UI components, widget cleanup rules, saved window position behavior, feature tab ownership, or AceGUI annotation expectations change.
