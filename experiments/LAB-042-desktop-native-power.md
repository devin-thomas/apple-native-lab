---
id: "LAB-042"
title: "Desktop Native Power"
state: "specified"
milestone: "M2"
category: "Mac"
depends_on: ["LAB-001", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-042 — Desktop Native Power

## The moment

Use a command palette, menu-bar status, multiwindow documents, and one deliberate automation entry point.

## Scope and native leverage

**Hosts:** Mac only.

**Primary APIs:** SwiftUI scenes, AppKit, Services, optional scripting. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** DesktopCommand, WindowRoute. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use native window/menu/keyboard conventions
2. Add a Services-style selected-text import
3. Expose an allowlisted scriptable operation if appropriate
4. Restore scene state without reopening private content unexpectedly

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Every gesture-only action has a discoverable alternate path.
- [ ] Closing a window does not destroy its document.
- [ ] No arbitrary shell text is executed from an intent.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Desktop scripting is a separate permission boundary, not a cross-platform universal ability.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Standard menu command and file import.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/desktop-native-power/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-042-A.md) → [qualification ticket](../tickets/LAB-042-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S57](../docs/SOURCE_INDEX.md#s57), [S38](../docs/SOURCE_INDEX.md#s38). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
