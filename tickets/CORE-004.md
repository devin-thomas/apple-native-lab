---
id: "CORE-004"
title: "Build capability probes and permission staging"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001"]
---

# CORE-004 — Build capability probes and permission staging

## Goal

Replace platform-name assumptions with inspectable readiness and a useful fallback.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Packages/LabSupport capability registry and host capability UI.

## Implementation steps

1. Model hardware, OS/API, asset, permission, entitlement, service, and verification gates separately
2. Implement no-prompt startup probes where supported and unknown state where not queryable
3. Request permissions only from an explicit feature action
4. Expose an explainable unavailable state and fallback routing

## Acceptance criteria

- [ ] Launching the core does not trigger a permission storm.
- [ ] Unknown support is never shown as verified readiness.
- [ ] Denied permissions produce the documented alternate route.
- [ ] Probes cannot import unsupported frameworks into another platform target.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
