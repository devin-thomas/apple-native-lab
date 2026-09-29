---
id: "LAB-027-A"
title: "Implement Sound in Space"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-023-B"]
---

# LAB-027-A — Implement Sound in Space

## Goal

Move a sound behind a virtual wall and hear the scene change while inspecting the sound graph.

## Authority and scope

Read the [governing specification](../experiments/LAB-027-sound-in-space.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** sound-in-space module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use original sounds at safe initial volume
3. Add emitter position and occluding geometry
4. Offer a binaural/channel-aware rendering path
5. Enable compatible head tracking only when available
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Switching output route preserves safe gain.
- [ ] Missing headphones disables only head tracking.
- [ ] No double-spatialization configuration is silently accepted.
- [ ] Fallback is usable: Stereo mix and visible scene controls..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** This is an app-owned spatial mix, not global control over music from other apps.

**Research:** [S23](../docs/SOURCE_INDEX.md#s23), [S24](../docs/SOURCE_INDEX.md#s24).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
