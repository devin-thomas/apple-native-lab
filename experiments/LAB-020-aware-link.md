---
id: "LAB-020"
title: "Aware Link"
state: "specified"
milestone: "M4"
category: "Continuity"
depends_on: ["LAB-019", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-020 — Aware Link

## The moment

Transfer a sample asset over a deliberately paired direct link and display the measured transport difference.

## Scope and native leverage

**Hosts:** Supported devices only; iPhone/iPad proof before any broader promise.

**Primary APIs:** WiFiAware, DeviceDiscoveryUI, Network. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** TransferManifest, CapabilityProbe. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Check WACapabilities instead of model-name assumptions
2. Pair using system discovery
3. Transfer bounded chunks with checksums
4. Cancel, resume, and compare against ordinary LAN

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unsupported hardware never advertises an Aware service.
- [ ] A cancelled transfer leaves no corrupt final file.
- [ ] Device trust removal prevents reconnection.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Wi-Fi Aware is not a universal Mac/Watch/TV mesh. A BLE or Wi-Fi board is not automatically Aware-capable.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

The LAN adapter from Local Constellation supplies the same operation.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/aware-link/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-020-A.md) → [qualification ticket](../tickets/LAB-020-B.md).

**Lab dependencies:** [LAB-019](LAB-019-local-constellation.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S17](../docs/SOURCE_INDEX.md#s17), [S31](../docs/SOURCE_INDEX.md#s31). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
