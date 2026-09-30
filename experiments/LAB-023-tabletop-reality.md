---
id: "LAB-023"
title: "Tabletop Reality"
state: "implemented"
milestone: "M3"
category: "Spatial"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-023 — Tabletop Reality

## The moment

Place a small interactive system on a real table, move around it, and inspect occlusion and tracking quality.

## Scope and native leverage

**Hosts:** ARKit-supported iPhone/iPad; non-AR Mac viewer.

**Primary APIs:** ARKit, RealityKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** WorldAnchor, SceneState, TrackingStatus. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Acquire a plane with coaching UI
2. Place original procedural objects
3. Persist only supported mapping data with consent
4. Recover from relocalization failure

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Tracking loss suspends precision interactions.
- [ ] A reset destroys only lab-owned anchors.
- [ ] An accessibility list exposes every meaningful object.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Handheld AR, not headset passthrough or guaranteed persistent world tracking.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Orbitable 3D scene with mouse/touch controls.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/tabletop-reality/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-023-A):

- `Packages/LabDomain` and `Packages/LabStore`: the lab-owned anchor (`LabAnchor`, `AnchorPose`, `FixtureKey`), the `placeAnchor`, `moveAnchor`, and `removeAnchor` operations, Reset Demo removing every anchor, and store schema version 4. The spec's `WorldAnchor` is named `LabAnchor`, so it never shadows visionOS ARKit's `WorldAnchor`.
- `Packages/LabFeatures/Sources/TabletopReality/`: the original procedural kit (`Resources/tabletop-kit.json`), `TabletopPlanner` (placement rules and operations), `TrackingStatus` and `InteractionGate`, `SceneDescription` (the accessibility list), `RelocalizationWatch`, `TrackingReplay`, `LabAnchorNames`, `MappingPolicy`, `TabletopRoute`, and `SequentialRun`. It depends on LabDomain and LabSupport and imports neither RealityKit nor ARKit.
- `Apps/Shared/TabletopReality/`: `TabletopSession`, the RealityKit scene (`TabletopSceneController`), the virtual table and its controls, the iPhone page pushed from this experiment's catalog page, and the live AR adapter (`LiveTabletop`, iPhone and iPad only). The Mac shows the same parts in its window (`Apps/Mac/Window/TabletopColumns.swift`), reached from the sidebar, View › Tabletop Reality (⌘9), and the catalog page.

## Implementation notes (LAB-023-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs. These are compile, Mac, and simulator facts, not device proof.

- `RealityView` with `RealityViewCameraContent` is iOS 18, macOS 15, and tvOS 26. `realityViewCameraControls(_:)` and `CameraControls.orbit` are iOS 18 and macOS 15, unavailable on tvOS. `RealityViewCamera.spatialTracking` is iOS only; the virtual table uses the default virtual camera everywhere. `SpatialTapGesture().targetedToAnyEntity()` gives an `EntityTargetValue`, whose `hitTest(point:in:)` returns scene-space hits, on iOS 18 and macOS 15.
- `ARView` is iOS and tvOS 26; the live adapter uses it with `ARWorldTrackingConfiguration` because it needs the session: camera tracking state, `ARCoachingOverlayView`, `worldMappingStatus`, `getCurrentWorldMap`, `initialWorldMap`, and `sessionShouldAttemptRelocalization`. All are in the iOS 27.0 device and simulator SDKs, so the adapter compiles for both; the simulator reports `ARWorldTrackingConfiguration.isSupported` false.
- The route comes from the existing world-tracking capability report. The Mac excludes the probe, a simulator reports no support, and a source build declares no `NSCameraUsageDescription`, so each of those gets the virtual table with the deciding gate as its reason. The camera is asked for only by Start AR Camera, through `PermissionStager`.
- Poses are whole millimeters and degrees in the table's own frame, so the same arrangement shows on the virtual table and, relative to the placed table origin, in AR. The live adapter adds one session anchor, the table origin, named with the `nativelab.tabletop.` prefix; resets remove only anchors with that prefix, never ARKit's planes.
- Precision interactions (place, move, turn, the starter scene) run only while tracking is normal or on the virtual table. Selecting, the list, removal, and Clear Table run in every state. After 20 seconds of relocalization the adapter offers Keep Looking and Start Fresh; objects keep their places on the table either way.
- The world map is written only after the consent dialog, with complete file protection and excluded from backup, under Application Support. It never enters the store, a receipt, or an export.
- Occlusion uses scene reconstruction where `supportsSceneReconstruction(.mesh)` is true and person segmentation where supported; the AR screen says which, or that there is none.

## Delivery

[Implementation ticket](../tickets/LAB-023-A.md) → [qualification ticket](../tickets/LAB-023-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S40](../docs/SOURCE_INDEX.md#s40). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
