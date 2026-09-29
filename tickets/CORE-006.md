---
id: "CORE-006"
title: "Enforce import, authorization, logging, and export safety"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-002", "CORE-003"]
---

# CORE-006 — Enforce import, authorization, logging, and export safety

## Goal

Make the trust boundaries real before shared text, media, and generated proposals enter the system.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Domain validation, staging service, diagnostic/export policy tests.

## Implementation steps

1. Implement staged import size/path/hash limits and cancellation
2. Add scoped short-lived authorization grants at commit
3. Provide metadata-only diagnostics and selected redacted export
4. Write hostile-input and unauthorized-operation test fixtures

## Acceptance criteria

- [ ] A path traversal/archive expansion attempt is rejected before adoption.
- [ ] Imported instruction text cannot expand tool permissions.
- [ ] No default log contains raw prompts, filenames, tokens, or personal content.
- [ ] A cancelled import leaves no final adopted object.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
