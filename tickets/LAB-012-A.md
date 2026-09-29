---
id: "LAB-012-A"
title: "Implement Point, Inspect, Propose"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-007-B", "LAB-010-B"]
---

# LAB-012-A — Implement Point, Inspect, Propose

## Goal

Inspect an object or screenshot and turn observations into a reviewable lab record.

## Authority and scope

Read the [governing specification](../experiments/LAB-012-point-inspect-propose.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** point-inspect-propose module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Begin with a user-selected image
3. Run deterministic OCR/barcode where suitable
4. Offer a model-generated interpretation with image provenance
5. Add optional supported system visual-search participation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Barcode payloads cannot execute actions.
- [ ] Photos containing private text remain local by default.
- [ ] Uncertain recognition stays an editable suggestion.
- [ ] Fallback is usable: Image picker plus OCR and manual fields..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** System Visual Intelligence participation is not the same as arbitrary visual-agent control. Camera observation is not identity recognition.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06), [S55](../docs/SOURCE_INDEX.md#s55), [S62](../docs/SOURCE_INDEX.md#s62).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
