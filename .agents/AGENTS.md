# .agents/AGENTS.md

## Scope

`.agents/` owns repo-local, tool-neutral agent assets that should travel with the addon for any collaborator using Codex, Claude Code, Copilot, or another agentic coding system.

## Owned Files

- `README.md`: human-readable orientation for repo-local agent assets.
- `skills/ace3-addon-manager/`: shared Ace3 addon skill copied from the user skill library.
- `skills/agents-documentation-bootstrap/`: shared documentation-first AGENTS skill copied from the user skill library.

## Contracts

- Keep `.agents/` tool-neutral. Do not make `.codex/`, `.claude/`, or another vendor-specific directory the canonical shared source unless explicitly requested.
- Store reusable agent workflows under `.agents/skills/<skill-name>/` with a `SKILL.md` at the skill root.
- Preserve referenced `references/`, `scripts/`, `agents/`, and asset folders when copying a skill so its instructions remain usable offline from the repo.
- Treat user-level skill copies as install targets or personal overrides; the repo-local copies are the shared project baseline.
- Do not add `.agents/` files to `smart_rez.toc`; these files are documentation/tooling assets and must never load in WoW.

## Child Documentation

No child `AGENTS.md` files exist yet. Add one only if a skill family becomes a maintained subsystem with rules that should not live in this broad asset contract.

## Doc Updates

Update this file when repo-local skill layout, shared agent asset ownership, synchronization rules, or vendor/tooling assumptions change.
