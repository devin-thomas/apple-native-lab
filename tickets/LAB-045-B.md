---
id: "LAB-045-B"
title: "Qualify and document Ink Has Structure"
status: "planned"
milestone: "M4"
kind: "qualification"
depends_on: ["LAB-045-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-045-B — Qualify and document Ink Has Structure

## Goal

Prove Ink Has Structure on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-045-ink-has-structure.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** ink-has-structure tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Undo preserves anchoring after document resize; Non-Pencil users complete the task; Unsupported pencil gestures are absent, not broken
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Undo preserves anchoring after document resize.
- [ ] Non-Pencil users complete the task.
- [ ] Unsupported pencil gestures are absent, not broken.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPad/Pencil optional; touch on iPhone and pointer on Mac.

**Unavailable path:** Mouse/touch annotations and typed notes.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
