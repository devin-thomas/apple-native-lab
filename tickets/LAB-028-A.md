---
id: "LAB-028-A"
title: "Implement Recognize Our Audio"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-013-B"]
---

# LAB-028-A — Implement Recognize Our Audio

## Goal

Play an original reference clip anywhere and let a second screen find the matching point.

## Authority and scope

Read the [governing specification](../experiments/LAB-028-recognize-our-audio.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** recognize-our-audio module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Build a catalog from rights-cleared fixture audio
3. Attach time-indexed cue metadata
4. Match from explicit microphone capture
5. Debounce repeated matches and expose no-match state
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] No-match does not trigger a cue.
- [ ] A repeated match cannot spam side effects.
- [ ] Stopped capture releases the microphone.
- [ ] Fallback is usable: Select reference clip and time manually..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Exact prerecorded-audio matching, not a general sound classifier or live-song understanding.

**Research:** [S25](../docs/SOURCE_INDEX.md#s25), [S26](../docs/SOURCE_INDEX.md#s26).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
