---
id: "LAB-005-B"
title: "Qualify and document Live Session Beacon"
status: "planned"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-005-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-005-B — Qualify and document Live Session Beacon

## Goal

Prove Live Session Beacon on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-005-live-session-beacon.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** live-session-beacon tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: No activity remains active after terminal state; Unknown total work is indeterminate, not fabricated percent; Force-quit/relaunch restores the job truth
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] No activity remains active after terminal state.
- [ ] Unknown total work is indeterminate, not fabricated percent.
- [ ] Force-quit/relaunch restores the job truth.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone; system-mediated companion presentations probed.

**Unavailable path:** In-app job panel and optional completion notification.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
