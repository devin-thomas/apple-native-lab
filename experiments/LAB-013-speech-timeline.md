---
id: "LAB-013"
title: "Speech Timeline"
state: "specified"
milestone: "M2"
category: "Audio"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-013 — Speech Timeline

## The moment

Record or import speech and scrub a time-aligned transcript that improves while you watch.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac subject to language/device support.

**Primary APIs:** SpeechAnalyzer, SpeechTranscriber, AssetInventory. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** TranscriptSegment, MediaTimeRange. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Request recording only after an explicit start
2. Separate provisional text from finalized segments
3. Handle required model downloads transparently
4. Export original audio reference and text timing

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Route changes do not silently lose the session.
- [ ] Final segments do not duplicate provisional text.
- [ ] Transcript corrections preserve the original media timestamps.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No assumption of speaker identification, perfect names, or access to calls/other apps audio.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Import a caption fixture or annotate manually; unsupported languages are stated.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/speech-timeline/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-013-A.md) → [qualification ticket](../tickets/LAB-013-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S10](../docs/SOURCE_INDEX.md#s10). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
