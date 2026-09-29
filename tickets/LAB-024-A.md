---
id: "LAB-024-A"
title: "Implement Room Ledger"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-023-B", "LAB-008-B"]
---

# LAB-024-A — Implement Room Ledger

## Goal

Turn a scanned room into an editable semantic inventory and compare the scan to manual corrections.

## Authority and scope

Read the [governing specification](../experiments/LAB-024-room-ledger.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** room-ledger module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Ask for camera permission at scan start
3. Capture walls/openings and coarse furniture categories
4. Attach editable notes to selected elements
5. Export a redacted model with a privacy preview
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Raw room scans never enter public artifacts.
- [ ] Unsupported scanner opens a manual floor-plan path.
- [ ] Measurement edits retain scan provenance.
- [ ] Fallback is usable: Bundled fictional room plus manual dimensions..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Not survey-grade measurements, cable detection, or reliable identification of every device.

**Research:** [S20](../docs/SOURCE_INDEX.md#s20).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
