---
id: "LAB-046"
title: "Pocket Render Museum"
state: "specified"
milestone: "M3"
category: "Graphics"
depends_on: ["LAB-023", "LAB-030"]
source_review: "2026-09-29"
---

# LAB-046 — Pocket Render Museum

## The moment

Flip between deliberately constrained retro rendering and modern material/lighting while the same scene stays readable.

## Scope and native leverage

**Hosts:** Metal-capable iPhone/iPad/Mac/TV with feature probes.

**Primary APIs:** Metal, RealityKit interoperability where justified. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** RenderPreset, SceneSeed, QualityBudget. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use original geometric assets
2. Separate affine/low-resolution stylistic effects from actual hardware emulation
3. Offer deterministic scene replay
4. Scale quality against measured frame time and temperature

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Effects preserve accessible overlays.
- [ ] A slower GPU selects an explicit quality tier.
- [ ] A replay uses the same seed and simulation step.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Not cycle-accurate console emulation; no ROM, BIOS, ripped characters, or trademarked boot screens.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Basic unlit renderer or recorded original preview labeled as a preview.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/pocket-render-museum/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-046-A.md) → [qualification ticket](../tickets/LAB-046-B.md).

**Lab dependencies:** [LAB-023](LAB-023-tabletop-reality.md), [LAB-030](LAB-030-tactile-grammar.md).

**Primary-source references:** [S54](../docs/SOURCE_INDEX.md#s54). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
