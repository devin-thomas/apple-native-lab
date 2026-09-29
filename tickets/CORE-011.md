---
id: "CORE-011"
title: "Produce an independently buildable public release"
status: "planned"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-012"]
---

# CORE-011 — Produce an independently buildable public release

## Goal

Package a real tested release from the public root without adjacent data or invented installers.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Release scripts, manifest, distribution instructions, public changelog.

## Implementation steps

1. Build from a fresh checkout using the documented profiles
2. Inventory source, dependencies, assets, and license notices
3. Create allowlisted source and supported signed binary artifacts where actually available
4. Test the documented source-build/install path and publish only truthful compatibility/evidence notes

## Acceptance criteria

- [ ] The release ZIP includes no local config, databases, secrets, neighboring projects, or model downloads.
- [ ] The source build needs no maintainer account or hidden dependency.
- [ ] A claimed installable binary is tested through its actual supported installation route.
- [ ] The README changes from documentation-only only when source and evidence justify it.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
