---
id: "LAB-011-A"
title: "Implement Model Routing Observatory"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-010-B"]
---

# LAB-011-A — Implement Model Routing Observatory

## Goal

See where a request would run, what may leave the device, and why a larger model is or is not available.

## Authority and scope

Read the [governing specification](../experiments/LAB-011-model-routing-observatory.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** model-routing-observatory module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Keep local-only as the default policy
3. Model PCC eligibility separately from model availability
4. Show exact outgoing fields before a cloud request
5. Record route and usage without raw prompt telemetry
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Cloud-off causes zero cloud requests.
- [ ] Missing entitlement is an explained gate.
- [ ] Exhausted quota never silently switches to a paid provider.
- [ ] Fallback is usable: Local generation or manual workflow; no mandatory third-party key..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** PCC requires qualifying program enrollment, account entitlement, eligible distribution and user availability; not a free API for every source build.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06), [S07](../docs/SOURCE_INDEX.md#s07).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
