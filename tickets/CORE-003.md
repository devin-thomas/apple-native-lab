---
id: "CORE-003"
title: "Build local persistence and original fixture namespaces"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-002"]
---

# CORE-003 — Build local persistence and original fixture namespaces

## Goal

Provide useful offline state while preventing demo resets and migrations from losing imported user data.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Packages/LabStore, Fixtures, migration tests.

## Implementation steps

1. Select and record a transactional store implementation
2. Implement schema versioning and a deterministic fixture seed
3. Separate demo namespace from user-imported namespace
4. Implement reset, migration, conflict, and recovery tests

## Acceptance criteria

- [ ] An interrupted transaction leaves either the old or complete new state.
- [ ] Reset Demo preserves a deliberately imported user record.
- [ ] A released schema migration preserves stable IDs and unknown supported metadata.
- [ ] A corrupt fixture import does not prevent the next valid one.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
