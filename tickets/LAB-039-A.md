---
id: "LAB-039-A"
title: "Implement Tiny Doorway"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-008-B"]
---

# LAB-039-A — Implement Tiny Doorway

## Goal

Scan a code or open a link and arrive at one tightly scoped native action instead of a giant onboarding funnel.

## Authority and scope

Read the [governing specification](../experiments/LAB-039-tiny-doorway.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** tiny-doorway module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use an original local demo action
3. Validate domain/path and untrusted parameters
4. Offer a minimal App Clip target after setup
5. Hand off confirmed state to the full app when supported
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Malformed links cannot execute privileged actions.
- [ ] Offline invocation has an explained fallback.
- [ ] No public hosting dependency is required for core build.
- [ ] Fallback is usable: Web information page or full-app deep link, with no forced installation promise..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** App Clip invocation needs deployment configuration; a custom URL scheme alone is not equivalent.

**Research:** [S52](../docs/SOURCE_INDEX.md#s52).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
