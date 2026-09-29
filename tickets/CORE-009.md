---
id: "CORE-009"
title: "Implement replayable demonstrations and evidence export"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-003", "CORE-006", "CORE-007"]
---

# CORE-009 — Implement replayable demonstrations and evidence export

## Goal

Turn each successful experiment into an inspectable demonstration without inventing test results.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Demo runner, evidence exporter, original showcase fixtures.

## Implementation steps

1. Add fixture reset and scripted local action sequences
2. Record receipts and measured intervals using declared timebases
3. Build a selected-artifact export preview with rights/privacy review
4. Include hashes, toolchain/adapter metadata, failures, and untested areas

## Acceptance criteria

- [ ] Replaying a deterministic fixture produces the same domain result.
- [ ] An unrun step cannot acquire a passing badge.
- [ ] An export does not include adjacent directories or hidden source media.
- [ ] Every published performance claim links to a measured run.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
