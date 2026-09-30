---
id: "LAB-031-A"
title: "Implement Native Screening Room"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "CORE-013", "LAB-008-B"]
---

# LAB-031-A — Implement Native Screening Room

## Goal

Watch a rights-cleared clip, switch native playback surfaces, and resume without losing position or captions.

## Authority and scope

Read the [governing specification](../experiments/LAB-031-native-screening-room.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** native-screening-room module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Import or use original sample media
3. Use native playback controls and remote commands
4. Add caption/track selection
5. Probe PiP and AirPlay per platform
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Audio interruptions and route changes preserve correct state.
- [ ] Caption selection survives a presentation change.
- [ ] Unavailable codec or protected content shows a real error.
- [ ] Fallback is usable: In-app local playback using a small universally supported fixture..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No DRM extraction or conversion of arbitrary streaming URLs into downloadable media.

**Research:** [S41](../docs/SOURCE_INDEX.md#s41).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
