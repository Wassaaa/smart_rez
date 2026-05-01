# Documentation-First AGENTS.md Templates

## Mandatory Enforcement Block

Place this near the top of the generated root `AGENTS.md` before project-specific sections:

```markdown
## Documentation First

DOCUMENTATION IS THE MOST IMPORTANT PART OF THIS PROJECT.

Documentation is the project memory, architecture contract, onboarding path, and agent safety rail. Treat every `AGENTS.md` file as binding guidance for the code under its directory, not as optional notes.

Poor documentation causes agent behavior drift, architecture drift, duplicated work, incorrect assumptions, and changes in the wrong layer. A code change that leaves known documentation drift behind is not done.

AGENTS.md UPDATES ARE PART OF THE SAME CHANGE, NOT A FOLLOW-UP TASK. If you change code, config, tests, scripts, assets, docs, or any other project file, update the closest owning `AGENTS.md` in that same pass. Do not plan to update agent documentation later.

Before changing code, read:

1. the closest `AGENTS.md` for the files you will touch
2. every parent `AGENTS.md` up to the repository root
3. the root `AGENTS.md` index to discover sibling or child contracts that may apply

Always update documentation in the same session as code changes:

- update the closest owning `AGENTS.md` in the same implementation pass as the code/config/test/script/asset/doc change
- update parent docs when a change affects architecture, ownership, workflow, public contracts, product constraints, commands, state, configuration, verification, deployment, or cross-cutting behavior
- update this root index whenever an `AGENTS.md` file is added, removed, moved, or renamed
- create a nested `AGENTS.md` when a directory becomes a stable subsystem, package, feature area, service, route family, adapter family, component family, command family, test harness, or ownership boundary
- remove stale or contradictory instructions immediately
- keep high-level docs focused on principles, ownership, stable contracts, architecture, and boundaries
- push implementation details down into local docs
- keep lower-level docs concrete, explicit, and practical
- do not finish a change that leaves known documentation drift behind

If documentation and code disagree, treat that as documentation drift or architecture drift. Fix the drift by either updating docs to match the intended architecture or updating code to match the documented contract.

`README.md` is public-facing. It may contain the project pitch, quick start, setup, screenshots, and common commands. It must not become a competing implementation contract. Durable architecture, workflow, ownership, and agent-facing rules belong in `AGENTS.md`.
```

## Root AGENTS.md Starter

```markdown
# AGENTS.md

## Documentation First

DOCUMENTATION IS THE MOST IMPORTANT PART OF THIS PROJECT.

Documentation is the project memory, architecture contract, onboarding path, and agent safety rail. Treat every `AGENTS.md` file as binding guidance for the code under its directory, not as optional notes.

Poor documentation causes agent behavior drift, architecture drift, duplicated work, incorrect assumptions, and changes in the wrong layer. A code change that leaves known documentation drift behind is not done.

AGENTS.md UPDATES ARE PART OF THE SAME CHANGE, NOT A FOLLOW-UP TASK. If you change code, config, tests, scripts, assets, docs, or any other project file, update the closest owning `AGENTS.md` in that same pass. Do not plan to update agent documentation later.

Before changing code, read:

1. the closest `AGENTS.md` for the files you will touch
2. every parent `AGENTS.md` up to the repository root
3. the root `AGENTS.md` index to discover sibling or child contracts that may apply

Always update documentation in the same session as code changes:

- update the closest owning `AGENTS.md` in the same implementation pass as the code/config/test/script/asset/doc change
- update parent docs when a change affects architecture, ownership, workflow, public contracts, product constraints, commands, state, configuration, verification, deployment, or cross-cutting behavior
- update this root index whenever an `AGENTS.md` file is added, removed, moved, or renamed
- create a nested `AGENTS.md` when a directory becomes a stable subsystem, package, feature area, service, route family, adapter family, component family, command family, test harness, or ownership boundary
- remove stale or contradictory instructions immediately
- keep high-level docs focused on principles, ownership, stable contracts, architecture, and boundaries
- push implementation details down into local docs
- keep lower-level docs concrete, explicit, and practical
- do not finish a change that leaves known documentation drift behind

If documentation and code disagree, treat that as documentation drift or architecture drift. Fix the drift by either updating docs to match the intended architecture or updating code to match the documented contract.

`README.md` is public-facing. Durable architecture, workflow, ownership, and agent-facing implementation contracts belong in `AGENTS.md`.

## Documentation Shape

Every `AGENTS.md` should answer, in this order when practical:

1. what this scope owns
2. which files, directories, surfaces, or workflows it owns
3. which stable contracts it enforces
4. how child docs divide more specific detail
5. what changes require doc updates
6. what verification is expected for this scope

Parent docs explain boundaries, ownership maps, stable contracts, and cross-cutting rules. Child docs explain concrete behavior, local file structure, state/config rules, APIs, commands, gotchas, and verification.

## AGENTS File Index

This index must be exhaustive for repo `AGENTS.md` files:

- `/AGENTS.md`

## Project

Describe what this project is, who it is for, and what it must not become.

## Top-Level Architecture

Describe stable top-level directories and ownership boundaries.

## Product And Safety Rules

Document safety, privacy, security, compliance, domain, platform, or user-impact constraints.

## Programming Guide

Document repo-wide engineering preferences, naming conventions, dependency rules, compatibility policy, and refactor boundaries.

## Verification

Document expected checks before finishing changes. Include targeted commands for each major project area.
```

## Child AGENTS.md Starter

```markdown
# <Scope>/AGENTS.md

## Scope

Describe what this directory owns.

## Owned Files

List important files, subdirectories, workflows, APIs, commands, UI surfaces, jobs, adapters, tests, or generated assets owned by this scope.

## Contracts

Document stable rules for this scope: state, data flow, APIs, permissions, dependencies, styles, events, lifecycle, load order, security, integrations, and local gotchas.

## Child Documentation

List child `AGENTS.md` files or state that none exist yet. Explain when a deeper doc should be added.

## Doc Updates

Describe what changes require this file, parent docs, or child docs to be updated.

## Verification

List the most relevant checks for this scope, or explain when no automated checks exist.
```

## Project Type Adaptation Guide

- Web app: routes, API clients, data fetching, UI conventions, state management, build/lint/test commands, browser support, accessibility.
- Backend service: domain models, routes/RPC, services, storage, migrations, queues/jobs, adapters, auth, observability, tests.
- Library/package: public API, compatibility policy, build outputs, release process, examples, fixtures, downstream contract tests.
- CLI/tooling repo: commands, config files, environment assumptions, filesystem side effects, exit codes, logging, fixtures.
- Game/mod/addon: runtime load order, platform APIs, secure/event constraints, saved state, UI layers, live-environment verification.
- Data/ML project: datasets, schemas, lineage, train/eval boundaries, generated artifacts, notebooks, reproducibility, model safety.
- Infrastructure repo: environments, modules, state backends, secrets, deployment approvals, drift checks, rollback rules.
- Docs/content repo: information architecture, source-of-truth rules, publication workflow, style guide, asset ownership, link checks.

## Documentation Maintenance Checklist

- Did I update the closest owning `AGENTS.md` in the same pass as every project file change?
- Did I update the parent doc if a boundary, workflow, command, safety rule, or verification changed?
- Did I update the root `AGENTS.md` index if docs moved?
- Did I add a child doc if this area became a stable subsystem?
- Did I remove stale or contradictory instructions?
- Did I keep public-facing information in `README.md` or `docs/` and implementation contracts in `AGENTS.md`?
- Did I document new commands, APIs, state, config, tests, deployment behavior, generated assets, or ownership rules?
- Did I avoid documenting generated files, caches, vendored dependencies, local DBs, secrets, or temporary artifacts as owned project structure?

Do not finish a change that leaves known documentation drift behind.
