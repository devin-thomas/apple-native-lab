---
id: "LAB-033-A"
title: "Implement Capture With Consent"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-013-B", "LAB-032-B"]
---

# LAB-033-A — Implement Capture With Consent

## Goal

Record one chosen window with an unmistakable capture state and export redacted diagnostics.

## Authority and scope

Read the [governing specification](../experiments/LAB-033-capture-with-consent.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** capture-with-consent module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use system selection for the capture source
3. Show persistent recording indication
4. Handle source closure and permission revocation
5. Finalize or recover the recording after interruption
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Unselected windows are never added automatically.
- [ ] Revocation stops capture promptly.
- [ ] A demo export omits filenames and incidental private content.
- [ ] Fallback is usable: Import an original screen recording..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Protected content may be unavailable. No hidden screen/audio capture or bypassing TCC.

**Research:** [S42](../docs/SOURCE_INDEX.md#s42), [S41](../docs/SOURCE_INDEX.md#s41).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
