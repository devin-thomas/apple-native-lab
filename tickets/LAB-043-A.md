---
id: "LAB-043-A"
title: "Implement Respectful Attention"
status: "planned"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-004-B"]
---

# LAB-043-A — Implement Respectful Attention

## Goal

Compare an ordinary reminder, an app Focus filter, and a user-authorized alarm without spamming the system.

## Authority and scope

Read the [governing specification](../experiments/LAB-043-respectful-attention.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** respectful-attention module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Preview when and why attention is requested
3. Schedule app-owned notifications or alarm only by consent
4. Filter only lab content for a selected Focus
5. Provide one cancel-all-lab-alerts action
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Denied permissions do not trigger repeated prompts.
- [ ] Timezone changes retain intended date semantics.
- [ ] Cancel removes only lab-owned schedules.
- [ ] Fallback is usable: In-app agenda and timers visible while foregrounded..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No entitlement bypass, automatic global Focus switching, or general control of Clock alarms.

**Research:** [S33](../docs/SOURCE_INDEX.md#s33), [S01](../docs/SOURCE_INDEX.md#s01).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
