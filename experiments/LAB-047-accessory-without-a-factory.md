---
id: "LAB-047"
title: "Accessory Without a Factory"
state: "specified"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-019", "LAB-041"]
source_review: "2026-09-29"
---

# LAB-047 — Accessory Without a Factory

## The moment

Give a tiny button/light peripheral a polished pairing, control, and firmware-version story.

## Scope and native leverage

**Hosts:** iPhone host; optional paired Watch; user-supplied compatible peripheral.

**Primary APIs:** AccessorySetupKit, CoreBluetooth, optional Core MIDI. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AccessoryIdentity, CommandCapability. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Begin with a simulated device contract
2. Pair one explicitly supported peripheral
3. Expose safe, reversible commands
4. Handle rename, removal, and offline state

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unknown firmware is refused or restricted.
- [ ] Unpairing invalidates the app trust record.
- [ ] A BLE-only device is never advertised as Wi-Fi Aware capable.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No hardware purchase is required for baseline; vendor SDK, MFi, and Aware support cannot be assumed.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Software peripheral simulator and a contract-level test suite.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/accessory-without-a-factory/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

## Delivery

[Implementation ticket](../tickets/LAB-047-A.md) → [qualification ticket](../tickets/LAB-047-B.md).

**Lab dependencies:** [LAB-019](LAB-019-local-constellation.md), [LAB-041](LAB-041-trust-desk.md).

**Primary-source references:** [S31](../docs/SOURCE_INDEX.md#s31), [S32](../docs/SOURCE_INDEX.md#s32). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
