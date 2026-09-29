---
id: "LAB-020-A"
title: "Implement Aware Link"
status: "planned"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-019-B", "LAB-008-B"]
---

# LAB-020-A — Implement Aware Link

## Goal

Transfer a sample asset over a deliberately paired direct link and display the measured transport difference.

## Authority and scope

Read the [governing specification](../experiments/LAB-020-aware-link.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** aware-link module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Check WACapabilities instead of model-name assumptions
3. Pair using system discovery
4. Transfer bounded chunks with checksums
5. Cancel, resume, and compare against ordinary LAN
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [ ] Unsupported hardware never advertises an Aware service.
- [ ] A cancelled transfer leaves no corrupt final file.
- [ ] Device trust removal prevents reconnection.
- [ ] Fallback is usable: The LAN adapter from Local Constellation supplies the same operation..
- [ ] Sensitive operations share the domain authorization/receipt path.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Wi-Fi Aware is not a universal Mac/Watch/TV mesh. A BLE or Wi-Fi board is not automatically Aware-capable.

**Research:** [S17](../docs/SOURCE_INDEX.md#s17), [S31](../docs/SOURCE_INDEX.md#s31).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
