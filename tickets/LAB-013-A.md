---
id: "LAB-013-A"
title: "Implement Speech Timeline"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-013-A — Implement Speech Timeline

## Goal

Record or import speech and scrub a time-aligned transcript that improves while you watch.

## Authority and scope

Read the [governing specification](../experiments/LAB-013-speech-timeline.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** speech-timeline module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Request recording only after an explicit start
3. Separate provisional text from finalized segments
4. Handle required model downloads transparently
5. Export original audio reference and text timing
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Route changes do not silently lose the session.
- [ ] Final segments do not duplicate provisional text.
- [ ] Transcript corrections preserve the original media timestamps.
- [ ] Fallback is usable: Import a caption fixture or annotate manually; unsupported languages are stated..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No assumption of speaker identification, perfect names, or access to calls/other apps audio.

**Research:** [S10](../docs/SOURCE_INDEX.md#s10).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
