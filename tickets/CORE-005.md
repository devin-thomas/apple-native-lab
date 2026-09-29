---
id: "CORE-005"
title: "Build native host navigation and the experiment registry"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-002", "CORE-003", "CORE-004"]
---

# CORE-005 — Build native host navigation and the experiment registry

## Goal

Create a pleasant native laboratory, not a wall of nonfunctional framework buttons.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Apps native host views and static feature descriptors.

## Implementation steps

1. Build Mac sidebar/detail, commands, Settings, and appropriate window behavior
2. Build adaptive iPhone catalog/detail/import navigation
3. Register experiments statically with lifecycle state, fallback, and source links
4. Add an action/receipt inspector and safe demo reset entry

## Acceptance criteria

- [ ] Catalog entries distinguish specified from implemented features.
- [ ] Mac essential actions have keyboard/menu access.
- [ ] Large text and small phone layouts do not hide the primary action.
- [ ] The host remains usable offline without accounts or keys.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
