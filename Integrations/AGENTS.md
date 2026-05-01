# Integrations/AGENTS.md

## Scope

`Integrations/` owns code that talks directly to optional or external addon APIs. It should keep integration-specific frame details, callbacks, and global assumptions out of feature logic.

## Owned Files

- `tsmLabelClick.lua`: TradeSkillMaster label/click integration behavior.

Auctionator-facing helper code currently also exists in `Core/ahShared.lua`, `Features/ahSelling.lua`, `Features/ahSniper.lua`, `UI/ahSellingUi.lua`, and `UI/ahSniperUi.lua`. Keep a clear boundary: integration details should move here when they become reusable adapter behavior.

## Contracts

- TSM is optional; never assume `TSM_API` exists.
- Auctionator-dependent code must nil-check optional frames, mixins, globals, and addon-provided APIs at load time.
- Keep external-addon globals documented in `Annotations/addon-globals.lua`.
- Do not make integration code responsible for feature UI layout or saved configuration.
- Prefer small adapter functions that return clear success/failure states over leaking external addon structures through the codebase.

## Child Documentation

No child `AGENTS.md` files exist yet. Add one if Auctionator, TSM, or another integration grows into a multi-file adapter family.

## Doc Updates

Update this file when optional addon assumptions, adapter ownership, supported integration APIs, or addon global annotations change.
