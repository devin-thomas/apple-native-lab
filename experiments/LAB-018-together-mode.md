---
id: "LAB-018"
title: "Together Mode"
state: "specified"
milestone: "M3"
category: "Continuity"
depends_on: ["LAB-019", "LAB-031"]
source_review: "2026-09-29"
---

# LAB-018 — Together Mode

## The moment

Invite another person into the same media inspection or drawing activity with late-join recovery.

## Scope and native leverage

**Hosts:** Supported iPhone, iPad, Mac; tvOS participation independently proved.

**Primary APIs:** GroupActivities, GroupSessionMessenger, AVPlayer coordination. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** SharedSession, ParticipantRole, ContentLocator. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Require explicit SharePlay activation
2. Synchronize state and participant roles
3. Make each participant resolve authorized media
4. Support pause, leave, and resynchronization

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Late join receives a complete state snapshot.
- [ ] A guest cannot perform owner-only destructive actions.
- [ ] Content rights failure does not fall back to streaming protected bytes.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

SharePlay is not arbitrary serverless background sync and does not grant media licenses.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local two-window simulation labeled as simulated; ordinary playback still works.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/together-mode/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-018-A.md) → [qualification ticket](../tickets/LAB-018-B.md).

**Lab dependencies:** [LAB-019](LAB-019-local-constellation.md), [LAB-031](LAB-031-native-screening-room.md).

**Primary-source references:** [S16](../docs/SOURCE_INDEX.md#s16), [S41](../docs/SOURCE_INDEX.md#s41). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
