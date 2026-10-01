---
id: "LAB-048"
title: "Commercial Frontier Desk"
state: "implemented"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-041"]
source_review: "2026-09-29"
---

# LAB-048 — Commercial Frontier Desk

## The moment

Learn how a public app reaches privileged system surfaces without treating entitlements as magic flags.

## Scope and native leverage

**Hosts:** iPhone primary; Mac in-app fallback. Three isolated optional package targets contain compile-only SDK probes; optional signed system hosts are not implemented.

**Primary APIs:** PushToTalk, CarPlay, FamilyControls/DeviceActivity. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** FrontierCapabilityCase, EntitlementEvidence. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Provide three tiny independent lifecycle probes
2. PTT: model channel join/leave before any live APNs server
3. CarPlay: build an allowed-category simulator view
4. Screen Time: self-authorized demo with clear revocation

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Missing managed approval does not break other targets.
- [ ] No PTT wake is used for unrelated work.
- [ ] Screen Time has a documented self-escape and never hides restrictions.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Three bounded spikes, not three production products. Real PTT networking and managed distribution approvals are external gates.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app protocol/lifecycle demonstrators labeled as simulations.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/commercial-frontier-desk/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-048-A.md) → [qualification ticket](../tickets/LAB-048-B.md).

**Lab dependencies:** [LAB-041](LAB-041-trust-desk.md).

**Primary-source references:** [S34](../docs/SOURCE_INDEX.md#s34), [S35](../docs/SOURCE_INDEX.md#s35), [S36](../docs/SOURCE_INDEX.md#s36). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.

## Implementation boundary (LAB-048-A)

The delivered fallback is three independent, receipt-backed local lifecycle simulations under
`Packages/LabFeatures/Sources/CommercialFrontier/` and `Apps/Shared/CommercialFrontier/`.
PTT models explicit foreground join/leave only, with no APNs, audio or background wake path.
CarPlay previews an audio-category fixture list inside the app; its separate CPListTemplate
factory is compile-only, not an external-display scene. Screen Time models individual consent,
one visible sample restriction and revocation without installing system restrictions.

Reset probe updates only that section's fixed local record. Revoke clears the simulated
restriction and authorization together. Live self-escape must clear all owned ManagedSettings
stores and stop owned DeviceActivity monitors before revoking individual authorization, and
must never shield the lab or Settings. No live cleanup is claimed here.

All used SDK symbols predate iOS 27; optional probes import only on iOS and are not linked by
baseline hosts. Missing managed approval has a usable fallback. CarPlay approval, PTT capability
and transport, Family Controls provisioning/distribution, optional executable hosts and live
adapter qualification remain external/unimplemented gates. See [ADR-LAB-048](../docs/adr/ADR-LAB-048.md),
[walkthrough](../evidence/LAB-048/README.md) and [installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md).
