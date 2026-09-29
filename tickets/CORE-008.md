---
id: "CORE-008"
title: "Separate capability-heavy targets from the baseline"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001", "CORE-004"]
---

# CORE-008 — Separate capability-heavy targets from the baseline

## Goal

Allow a new developer to build the core without qualifying every advanced entitlement.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Workspace target graph, entitlements per target, configuration documentation.

## Implementation steps

1. Define CoreLocal, SystemSurfaces, Companions, CloudOptional, and FrontierOptional profiles
2. Keep extension entitlements attached only to the correct executable
3. Add ignored local signing/container overrides with safe documented examples
4. Test the core with every optional profile disabled

## Acceptance criteria

- [ ] Missing PCC/CarPlay/File Provider setup cannot fail CoreLocal compilation.
- [ ] Identifiers are configurable without a maintainer-owned container.
- [ ] No target links frameworks unsupported on its platform by accident.
- [ ] The release manifest identifies which profiles were actually built.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
