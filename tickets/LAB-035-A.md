---
id: "LAB-035-A"
title: "Implement Access as a Superpower"
status: "planned"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-035-A — Implement Access as a Superpower

## Goal

Complete the same meaningful task visually, by VoiceOver, with keyboard control, and through a sonified chart.

## Authority and scope

Read the [governing specification](../experiments/LAB-035-access-as-a-superpower.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** access-as-a-superpower module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Create a data-backed chart with a text summary
3. Expose labels, grouping, actions, and rotor structure as appropriate
4. Add Audio Graphs for supported chart surfaces
5. Test Dynamic Type, contrast, reduce motion and transparency
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] No information is encoded by color alone.
- [ ] Keyboard and VoiceOver can finish the full task.
- [ ] An unsupported sonification API retains a table and summary.
- [ ] Fallback is usable: Semantic list/table and standard platform controls..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Accessibility is a release gate across all labs, not only this showcase; optional Assistive Access is a separate probe.

**Research:** [S29](../docs/SOURCE_INDEX.md#s29), [S30](../docs/SOURCE_INDEX.md#s30).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
