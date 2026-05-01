# Legacy/AGENTS.md

## Scope

`Legacy/` owns retired or reference-only code. Code here is not part of normal runtime behavior.

## Owned Files

- `snipeAuctionator.lua`: legacy Auctionator sniping reference.
- `SnipeAuctionator.xml`: legacy XML reference.

## Contracts

- Do not add `Legacy/` files to `smart_rez.toc` or runtime XML load paths unless the user explicitly asks to revive them.
- Treat this folder as historical context, not an implementation source of truth.
- If legacy behavior is revived, move the active implementation into the appropriate runtime layer and document the new ownership there.
- Do not copy legacy patterns into modern code without checking current Retail and addon API expectations.

## Child Documentation

No child `AGENTS.md` files exist yet.

## Doc Updates

Update this file when legacy files are removed, promoted, or reclassified.
