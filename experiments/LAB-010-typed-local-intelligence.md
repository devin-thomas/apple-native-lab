---
id: "LAB-010"
title: "Typed Local Intelligence"
state: "specified"
milestone: "M1"
category: "Intelligence"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-010 — Typed Local Intelligence

## The moment

Turn an ambiguous note into a typed proposal, then let a deterministic operation perform the approved change.

## Scope and native leverage

**Hosts:** Apple-Intelligence-capable iPhone/iPad/Mac.

**Primary APIs:** Foundation Models, guided generation, Tool. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** ExtractionProposal, ValidationIssue, EvidenceSpan. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Probe model readiness and language support
2. Generate a constrained draft from a bundled text fixture
3. Validate lengths, values, and cross-field rules
4. Preview the diff before commit

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Model-unavailable paths remain usable.
- [ ] Malicious imported instructions cannot authorize tools.
- [ ] Generated-but-invalid values never reach persistence.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Structured generation constrains form, not factual truth. No hidden network fallback or billing.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Deterministic sample parser and manual editor clearly labeled as non-model paths.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/typed-local-intelligence/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-010-A.md) → [qualification ticket](../tickets/LAB-010-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S06](../docs/SOURCE_INDEX.md#s06). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
