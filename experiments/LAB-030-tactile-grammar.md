---
id: "LAB-030"
title: "Tactile Grammar"
state: "specified"
milestone: "M2"
category: "Interaction"
depends_on: ["LAB-004"]
source_review: "2026-09-29"
---

# LAB-030 — Tactile Grammar

## The moment

Design three distinguishable tactile cues and compare actual device output rather than treating haptics as decoration.

## Scope and native leverage

**Hosts:** Capable iPhone, supported controllers, Watch system haptics separately.

**Primary APIs:** Core Haptics, GameController, Watch haptic APIs. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** CuePattern, DeviceHapticCapabilities. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Create success/warning/timing cues with original audio
2. Show visual and spoken equivalents
3. Route to supported device feedback
4. Provide a clear stop and intensity preference

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unsupported actuators never crash a cue.
- [ ] Muted haptics leave every task usable.
- [ ] Repeated cues obey rate and fatigue limits.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No arbitrary custom waveform parity on Watch; controller support differs by device.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Visual pulse and optional quiet audio.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/tactile-grammar/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-030-A.md) → [qualification ticket](../tickets/LAB-030-B.md).

**Lab dependencies:** [LAB-004](LAB-004-surface-deck.md).

**Primary-source references:** [S49](../docs/SOURCE_INDEX.md#s49), [S50](../docs/SOURCE_INDEX.md#s50). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
