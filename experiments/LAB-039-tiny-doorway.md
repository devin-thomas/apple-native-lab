---
id: "LAB-039"
title: "Tiny Doorway"
state: "specified"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-001", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-039 — Tiny Doorway

## The moment

Scan a code or open a link and arrive at one tightly scoped native action instead of a giant onboarding funnel.

## Scope and native leverage

**Hosts:** iPhone with optional App Clip; universal-link fallback elsewhere.

**Primary APIs:** App Clips, associated domains, universal links. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** InvocationContext, SignedLinkProposal. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use an original local demo action
2. Validate domain/path and untrusted parameters
3. Offer a minimal App Clip target after setup
4. Hand off confirmed state to the full app when supported

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Malformed links cannot execute privileged actions.
- [ ] Offline invocation has an explained fallback.
- [ ] No public hosting dependency is required for core build.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

App Clip invocation needs deployment configuration; a custom URL scheme alone is not equivalent.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Web information page or full-app deep link, with no forced installation promise.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/tiny-doorway/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-039-A.md) → [qualification ticket](../tickets/LAB-039-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S52](../docs/SOURCE_INDEX.md#s52). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
