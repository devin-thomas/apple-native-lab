---
id: "CORE-010"
title: "Establish accessible components and native review gates"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-005", "CORE-007"]
---

# CORE-010 — Establish accessible components and native review gates

## Goal

Make accessibility a shared component property, not late per-demo remediation.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Native shared components, accessibility fixtures, manual review checklist.

## Implementation steps

1. Audit labels, reading order, keyboard/focus, and meaningful state announcements
2. Test large text, contrast, reduced motion/transparency
3. Provide text alternatives for sound/haptics and semantic data summaries
4. Document manual assistive-technology checks in release evidence

## Acceptance criteria

- [ ] The core import/review/commit flow is usable without visual-only cues.
- [ ] A keyboard user can navigate and cancel all essential Mac operations.
- [ ] Reduced Motion does not remove functionality.
- [ ] Automated audit results are not represented as a full manual accessibility pass.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
