---
id: "LAB-046-A"
title: "Implement Pocket Render Museum"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-023-B", "LAB-030-B"]
---

# LAB-046-A — Implement Pocket Render Museum

## Goal

Flip between deliberately constrained retro rendering and modern material/lighting while the same scene stays readable.

## Authority and scope

Read the [governing specification](../experiments/LAB-046-pocket-render-museum.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** pocket-render-museum module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use original geometric assets
3. Separate affine/low-resolution stylistic effects from actual hardware emulation
4. Offer deterministic scene replay
5. Scale quality against measured frame time and temperature
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Effects preserve accessible overlays.
- [ ] A slower GPU selects an explicit quality tier.
- [ ] A replay uses the same seed and simulation step.
- [ ] Fallback is usable: Basic unlit renderer or recorded original preview labeled as a preview..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Not cycle-accurate console emulation; no ROM, BIOS, ripped characters, or trademarked boot screens.

**Research:** [S54](../docs/SOURCE_INDEX.md#s54).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
