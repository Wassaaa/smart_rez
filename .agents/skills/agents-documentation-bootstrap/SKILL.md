---
name: agents-documentation-bootstrap
description: Initialize or strengthen documentation-first AGENTS.md systems in any project, including strict same-pass AGENTS.md update enforcement. Use when the user asks to create, bootstrap, enforce, generate, reorganize, or upgrade agent instructions, AGENTS.md hierarchies, documentation-first contracts, repo documentation rules, or reusable agent onboarding contracts for a project.
---

# AGENTS Documentation Bootstrap

## Purpose

Use this skill to create a documentation-first `AGENTS.md` hierarchy for a project. The generated root contract must make this enforcement unmistakable:

```markdown
DOCUMENTATION IS THE MOST IMPORTANT PART OF THIS PROJECT.
```

Do not soften the enforcement into a vague reminder. Documentation is a binding work product: code changes that leave known documentation drift behind are incomplete.

The generated contract must explicitly require same-pass documentation edits. If an agent changes code, config, tests, scripts, assets, docs, or other project files, that same work pass must also update the closest owning `AGENTS.md`. Do not allow "update docs later" plans.

## Workflow

1. Inspect the project before writing contracts:
   - project purpose, audience, and product plan
   - stack, runtime, package manager, build/test tools
   - top-level source, test, docs, scripts, infrastructure, generated, vendor, and cache directories
   - entrypoints, load order, public APIs, commands, routes, jobs, plugins, adapters, UI surfaces, and state boundaries
   - safety, privacy, security, compliance, domain, platform, or user-impact constraints
   - existing README/docs that should remain public-facing versus agent-facing
2. Create or update root `AGENTS.md`:
   - put `## Documentation First` near the top, before architecture details
   - include the mandatory enforcement block from `references/templates.md`
   - include the rule that any project file change must update the closest owning `AGENTS.md` in the same pass
   - document project mission, architecture, safety rules, programming guide, verification, and the exhaustive `AGENTS.md` index
3. Add child `AGENTS.md` files for stable ownership boundaries:
   - top-level domains, packages, services, route families, component families, adapters, integrations, scripts, tests, plugins, or subsystems
   - any directory where future agents are likely to make mistakes without local guidance
4. Keep docs layered:
   - root docs own repo-wide principles, architecture, cross-cutting constraints, and the index
   - child docs own concrete local behavior, file ownership, APIs, state/config rules, gotchas, and verification
5. Verify before finishing:
   - root index exactly matches every active `AGENTS.md`
   - every project file change has a matching closest-owner `AGENTS.md` update in the same pass
   - generated/vendor/cache/temp directories are not documented as owned project structure
   - README/docs are not competing implementation contracts
   - code and docs do not knowingly disagree

## Reference

Read `references/templates.md` when generating or rewriting files. It contains:

- mandatory root enforcement block
- root `AGENTS.md` starter
- child `AGENTS.md` starter
- project type adaptation guide
- documentation maintenance checklist

## Rules

- Treat the project's own instructions and existing code as source material.
- Convert durable implementation rules into `AGENTS.md`; keep public narrative and onboarding in `README.md` or `docs/`.
- Enforce same-pass documentation edits: changing project files and updating the relevant `AGENTS.md` are one task, not two tasks.
- Never tell future agents to update `AGENTS.md` later. The generated contract must say the current pass is incomplete until the closest owning `AGENTS.md` has been updated.
- Keep enforcement language in generated files exact or stronger. Do not paraphrase it into soft guidance.
- Update the root index whenever an `AGENTS.md` file is added, removed, moved, or renamed.
- Do not create child docs for dependency folders, generated output, build caches, one-off temporary folders, or tiny directories whose rules are obvious from the parent.
- If documentation and code disagree, resolve the drift by updating docs to match the intended architecture or updating code to match the documented contract.
