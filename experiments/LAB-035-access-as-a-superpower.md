---
id: "LAB-035"
title: "Access as a Superpower"
state: "specified"
milestone: "M1"
category: "Accessibility"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-035 — Access as a Superpower

## The moment

Complete the same meaningful task visually, by VoiceOver, with keyboard control, and through a sonified chart.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; Watch/TV adapt primary tasks.

**Primary APIs:** SwiftUI accessibility, AXChartDescriptor, custom actions. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AccessibleTask, ChartSemantics, InteractionAlternative. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Create a data-backed chart with a text summary
2. Expose labels, grouping, actions, and rotor structure as appropriate
3. Add Audio Graphs for supported chart surfaces
4. Test Dynamic Type, contrast, reduce motion and transparency

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No information is encoded by color alone.
- [ ] Keyboard and VoiceOver can finish the full task.
- [ ] An unsupported sonification API retains a table and summary.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Accessibility is a release gate across all labs, not only this showcase; optional Assistive Access is a separate probe.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Semantic list/table and standard platform controls.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/access-as-a-superpower/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-035-A.md) → [qualification ticket](../tickets/LAB-035-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S29](../docs/SOURCE_INDEX.md#s29), [S30](../docs/SOURCE_INDEX.md#s30). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
