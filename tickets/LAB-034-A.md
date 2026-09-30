---
id: "LAB-034-A"
title: "Implement Television Stage"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "CORE-013", "LAB-019-B", "LAB-031-B"]
---

# LAB-034-A — Implement Television Stage

## Goal

Turn the TV into a stage with a user-chosen phone camera and a separate controller.

## Authority and scope

Read the [governing specification](../experiments/LAB-034-television-stage.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** television-stage module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Run a native tvOS scene with focus navigation
3. Connect a camera through the system picker
4. Show a local-camera stage and countdown
5. Pair an independent controller over LAN
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Camera disconnect leaves an actionable TV screen.
- [ ] Focus never becomes trapped on the preview.
- [ ] Phone camera-role conflict is detected before AR starts.
- [ ] Fallback is usable: Native TV display plus a synthetic camera fixture..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** One phone cannot be assumed to supply independent simultaneous ARKit and Continuity Camera sessions. Baseline TV generation must be confirmed.

**Research:** [S27](../docs/SOURCE_INDEX.md#s27).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
