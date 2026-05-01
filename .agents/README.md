# Repo-Local Agent Assets

This directory stores shared agent-facing assets that should travel with the repository.

Agents should read the root `AGENTS.md` first, then use the repo-local skills in `.agents/skills/` when a task matches a skill description.

Current shared skills:

- `skills/ace3-addon-manager/`: Ace3 World of Warcraft addon auditing and implementation guidance.
- `skills/agents-documentation-bootstrap/`: documentation-first `AGENTS.md` hierarchy guidance and templates.

These copies are intentionally tool-neutral. Codex can use the same `SKILL.md` layout directly or copy/symlink these skills into a user-level skills directory; other agents can still read the Markdown instructions and references.
