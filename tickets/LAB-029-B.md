---
id: "LAB-029-B"
title: "Qualify and document Audio Workshop"
status: "planned"
milestone: "M3"
kind: "qualification"
depends_on: ["LAB-029-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-029-B — Qualify and document Audio Workshop

## Goal

Prove Audio Workshop on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-029-audio-workshop.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** audio-workshop tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: No allocation or blocking I/O in render callbacks; Output route and sample-rate changes recover; Plugin state round-trips across host reload
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] No allocation or blocking I/O in render callbacks.
- [ ] Output route and sample-rate changes recover.
- [ ] Plugin state round-trips across host reload.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Mac and iPhone/iPad; AUv3 target isolated.

**Unavailable path:** Offline audio-file processing and on-screen MIDI events.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
