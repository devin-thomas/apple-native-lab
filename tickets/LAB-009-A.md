---
id: "LAB-009-A"
title: "Implement Documents Everywhere"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-009-A — Implement Documents Everywhere

## Goal

Preview a custom document in the system and browse an opt-in sample provider.

## Authority and scope

Read the [governing specification](../experiments/LAB-009-documents-everywhere.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** documents-everywhere module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Ship Quick Look support first
3. Add a separate local-fixture provider target
4. Enumerate and open tiny safe sample documents
5. Test conflicts and eviction before remote storage
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Quick Look works without provider activation.
- [ ] External edits preserve document revision rules.
- [ ] Provider disconnect never deletes the authoritative source.
- [ ] Fallback is usable: Document browser with previews; provider remains disabled until qualified..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** File Provider is a serious storage extension, not needed for ordinary sharing. No production cloud service in v1.

**Research:** [S14](../docs/SOURCE_INDEX.md#s14), [S22](../docs/SOURCE_INDEX.md#s22).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
