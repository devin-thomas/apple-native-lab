---
id: "LAB-037"
title: "Home Scene Sandbox"
state: "implemented"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-037 — Home Scene Sandbox

## The moment

Preview a home-scene diff, execute only selected harmless actions, and explain partial failure.

## Scope and native leverage

**Hosts:** iPhone/iPad; supported Mac client separately.

**Primary APIs:** HomeKit, Matter optional controller investigation. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AccessorySnapshot, SceneProposal. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use simulated lights first
2. Request access to the selected home
3. Preview on/off/brightness changes
4. Commit and report per-accessory outcomes

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A disconnected lamp does not mark the whole scene successful.
- [ ] Locks, doors, alarms, and heating are excluded by default.
- [ ] A revoked home permission stops live mode.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

HomeKit does not expose every vendor API; Matter controller work is separate from a HomeKit client.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Deterministic fictional home with no real accessories.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/home-scene-sandbox/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-037-A):

- `Packages/LabFeatures/Sources/HomeSceneSandbox/` holds everything except the views:
  - domain types `AccessorySnapshot`, `SceneProposal`, `SceneCommitReport`;
  - `FictionalHome` / `FictionalHomeSource` (CoreLocal path);
  - `ScriptedPermissionSource` for revoked-permission tests;
  - `HomeSceneSandbox` preview/commit over `HomeSceneBackend` → OperationService;
  - `HomeKitPlatformFacts` records installed-SDK symbols without linking HomeKit.
- `Apps/Shared/HomeSceneSandbox/` holds the host session, library backend, and views.
  - The Mac reaches it from the sidebar (⌃⌘6) and from this experiment's catalog page.
  - iPhone reaches it from the catalog page only.
- `Fixtures/home/` holds the original fictional-home JSON (IDs match `FictionalHome`).

HomeKit is not linked in CoreLocal. Live mode on iOS needs `com.apple.developer.homekit` and `NSHomeKitUsageDescription` in a separate opt-in build. The macOS 27.0 SDK has no HomeKit framework (`API_UNAVAILABLE(macos)`).

## Implementation notes (LAB-037-A)

Observed with Xcode 27.0 (27A266a), the iOS 27.0 SDK HomeKit headers, and this experiment's package tests on research. These are compile and fixture facts, not device proof.

- **Authorization.** `HMHomeManager.authorizationStatus` (`HMHomeManagerAuthorizationStatus`, iOS 13+) is unavailable on macOS. CoreLocal never links HomeKit; `HomeKitPlatformFacts` names the symbols and the entitlement gate.
- **Reachability.** `HMAccessory.isReachable` (iOS 8+) maps to `AccessorySnapshot.isReachable`. A disconnected fictional hallway lamp fails its outcome and keeps `sceneSucceeded` false.
- **Service types.** Lights use `HMServiceTypeLightbulb`; excluded by default: `HMServiceTypeLockMechanism`, `HMServiceTypeDoor`, `HMServiceTypeSecuritySystem`, `HMServiceTypeThermostat`. All `API_UNAVAILABLE(macos)`.
- **Writes.** Live writes would use `HMCharacteristic.writeValue(_:completionHandler:)` for `HMCharacteristicTypePowerState` and `HMCharacteristicTypeBrightness`. This build applies light changes only through the fictional source.
- **Receipts.** Every commit records one `createItem` or `updateItem` through OperationService as the app UI. Partial failure still records the run; the note explains which accessories failed.
- **Matter.** `HMAccessory.matterNodeID` (iOS 16.1) and `HMService.matterEndpointID` (iOS 18) exist in the SDK; this ticket does not implement a Matter controller.

## Delivery

[Implementation ticket](../tickets/LAB-037-A.md) → [qualification ticket](../tickets/LAB-037-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S44](../docs/SOURCE_INDEX.md#s44). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.

The implementation is deliberately fictional-only ([ADR-LAB-037](../docs/adr/ADR-LAB-037.md)). Access requests do not activate a live source in CoreLocal. Live commits are refused even with the test permission stand-in; a future opt-in adapter must authorize the external operation itself and account for irreversible partial writes. Fictional outcomes are calculated first, the run is admitted through OperationService, then in-memory lamps are updated. Reset restores lamp defaults and the owned run note; receipts remain. Stale previews and overlapping commit/reset requests are refused. Replays within a session submit the original operation again, so OperationService rechecks authorization without applying lights twice.
