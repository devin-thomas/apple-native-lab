---
id: "LAB-007-A"
title: "Implement Share Ingress Station"
status: "planned"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-007-A — Implement Share Ingress Station

## Goal

Share a page, image, or video into a staging inbox without losing the source context.

## Authority and scope

Read the [governing specification](../experiments/LAB-007-share-ingress-station.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** share-ingress-station module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Accept URL/text/image/movie attachments
3. Copy bounded data while extension access is valid
4. Write a durable inbox entry and finish promptly
5. Let the host app validate and process the staged item
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Cloud-backed attachments can be cancelled safely.
- [ ] Multiple attachments preserve order and provenance.
- [ ] Malformed and oversized payloads never block future imports.
- [ ] Fallback is usable: Host-app file picker and paste action; extension not required for core build..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Share extensions have constrained lifetime/memory. They do not scrape the host app or run a large media pipeline.

**Research:** [S13](../docs/SOURCE_INDEX.md#s13), [S11](../docs/SOURCE_INDEX.md#s11).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
