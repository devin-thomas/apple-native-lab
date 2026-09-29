---
id: "LAB-025-A"
title: "Implement Object Forge"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B", "LAB-032-B"]
---

# LAB-025-A — Implement Object Forge

## Goal

Scan an everyday object, inspect reconstruction failures, and share a viewable 3D artifact.

## Authority and scope

Read the [governing specification](../experiments/LAB-025-object-forge.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** object-forge module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Capture consented photographs with a quality checklist
3. Validate reconstruction availability separately
4. Run a cancellable reconstruction
5. Review scale, holes, and rights before USDZ export
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Reflective/textureless objects have an explained failure path.
- [ ] Cancel preserves usable source photos.
- [ ] Output scale is labeled known or uncalibrated.
- [ ] Fallback is usable: Original procedural sample mesh and a supplied consented photo fixture..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Scanning and reconstruction are separate gates. No claim that every Mac or every material reconstructs well.

**Research:** [S21](../docs/SOURCE_INDEX.md#s21), [S22](../docs/SOURCE_INDEX.md#s22).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
