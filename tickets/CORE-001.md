---
id: "CORE-001"
title: "Pin the toolchain and create independent core schemes"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: []
---

# CORE-001 — Pin the toolchain and create independent core schemes

## Goal

Establish an actual, reproducible Mac/iPhone workspace before API-specific implementation.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Workspace, safe Config defaults, script/build_and_run.sh, generated BUILD_STATUS documentation.

## Implementation steps

1. Inspect repository boundaries; initialize only this root if no Git repository exists
2. Record exact Xcode/Swift/SDK and compatible host macOS requirements
3. Create minimal native Mac and iPhone schemes with safe configurable bundle identifiers
4. Add a real Mac build-and-run entry point that opens the produced .app bundle

## Acceptance criteria

- [ ] A clean checkout compiles the minimal core schemes without private configuration.
- [ ] The selected deployment floor and advanced-adapter boundary are documented with actual compiler evidence.
- [ ] A new developer can change team/bundle prefix without editing application source.
- [ ] A missing optional capability is not linked into CoreLocal.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
