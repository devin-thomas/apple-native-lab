---
id: "LAB-033"
title: "Capture With Consent"
state: "specified"
milestone: "M3"
category: "Media"
depends_on: ["LAB-013", "LAB-032"]
source_review: "2026-09-29"
---

# LAB-033 — Capture With Consent

## The moment

Record one chosen window with an unmistakable capture state and export redacted diagnostics.

## Scope and native leverage

**Hosts:** Mac capture host; optional iPhone Continuity Camera.

**Primary APIs:** ScreenCaptureKit, AVFoundation, system content picker. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** CaptureSelection, RecordingSession, PrivacyMask. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use system selection for the capture source
2. Show persistent recording indication
3. Handle source closure and permission revocation
4. Finalize or recover the recording after interruption

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unselected windows are never added automatically.
- [ ] Revocation stops capture promptly.
- [ ] A demo export omits filenames and incidental private content.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Protected content may be unavailable. No hidden screen/audio capture or bypassing TCC.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Import an original screen recording.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/capture-with-consent/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-033-A.md) → [qualification ticket](../tickets/LAB-033-B.md).

**Lab dependencies:** [LAB-013](LAB-013-speech-timeline.md), [LAB-032](LAB-032-render-that-survives.md).

**Primary-source references:** [S42](../docs/SOURCE_INDEX.md#s42), [S41](../docs/SOURCE_INDEX.md#s41). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
