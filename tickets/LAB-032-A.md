---
id: "LAB-032-A"
title: "Implement Render That Survives"
status: "planned"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-032-A — Implement Render That Survives

## Goal

Start a render, leave the screen, return, and see a truthful recoverable job instead of a vanished spinner.

## Authority and scope

Read the [governing specification](../experiments/LAB-032-render-that-survives.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** render-that-survives module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Validate file access and destination capacity
3. Create a durable foreground job
4. Use continued processing only when qualified
5. Checkpoint, cancel, and atomically publish output
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Cancellation never replaces a good output with a partial file.
- [ ] Task expiration produces a resumable or clearly failed job.
- [ ] GPU-unavailable uses a supported lower-cost path.
- [ ] Fallback is usable: Keep the job foreground; Mac worker only while explicitly running..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Background APIs do not promise completion, launch at arbitrary times, or infinite agent execution.

**Research:** [S28](../docs/SOURCE_INDEX.md#s28), [S41](../docs/SOURCE_INDEX.md#s41).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
