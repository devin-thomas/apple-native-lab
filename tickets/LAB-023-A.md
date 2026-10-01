---
id: "LAB-023-A"
title: "Implement Tabletop Reality"
status: "done"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-023-A — Implement Tabletop Reality

## Goal

Place a small interactive system on a real table, move around it, and inspect occlusion and tracking quality.

## Authority and scope

Read the [governing specification](../experiments/LAB-023-tabletop-reality.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** tabletop-reality module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Acquire a plane with coaching UI
3. Place original procedural objects
4. Persist only supported mapping data with consent
5. Recover from relocalization failure
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Tracking loss suspends precision interactions. (Fixture and replay path. `InteractionGate` refuses place, move, turn, and the starter scene under every limited reason, interruption, not started, and not available, and allows selecting, the list, removal, and Clear Table (`trackingLossSuspendsEveryPrecisionInteractionAndNothingElse`, 7 cases). In the Mac host a limited status left the table and the receipt list unchanged and still allowed a removal (`trackingLossSuspendsPrecisionInteractionsButNotRemoval`). In the iOS 27.0 simulator the labeled tracking replay disabled Move and Turn while it ran. The live adapter maps ARKit's camera tracking state onto the same status, but no camera ran: that mapping is compiled, not observed.)
- [x] A reset destroys only lab-owned anchors. (Store path: Reset Demo removes every anchor and only anchors besides demo samples, never user data, in the in-memory and SQLite stores (`resetDemoRemovesEveryAnchorAndLeavesUserDataAlone`, `resetDemoRemovesEveryAnchorAndKeepsUserData`, `resetDemoRemovesOnlyTheLabsAnchorsAndDemoSamples` hosted); the schema refuses a user anchor. Live session: `LabAnchorNames.removals` picks only `nativelab.tabletop.`-named anchors and keeps planes and foreign anchors (`aResetRemovesOnlyTheLabsOwnSessionAnchors`); Reset Table Position uses it. That AR path has not run on a device.)
- [x] An accessibility list exposes every meaningful object. (`SceneDescription` lists the table and every stored anchor, including one whose fixture the kit does not know, with its place and heading in words (`theListNamesTheTableAndEveryAnchorIncludingOnesTheKitDoesNotDraw`). In the simulator each row read, for example, "Pine Tree, 27 cm right of center, 9 cm toward you, facing you, A pine tree with two tiers …", with Select, Move, Turn, and Remove VoiceOver actions. No person has used VoiceOver on it.)
- [x] Fallback is usable: Orbitable 3D scene with mouse/touch controls.. (The virtual table is the whole route on the Mac and in a simulator. In the iOS 27.0 simulator a tap on the drawn table placed a Windmill, Set Out Starter Scene placed the rest that fit, Move Right moved the Windmill 2 cm, and a drag orbited the scene to view it from below. The Mac hosted tests drove the same session (`everyChangeIsOneAppUIReceiptInTheLibrarysList`). The Mac window was not driven with a pointer.)
- [x] Sensitive operations share the domain authorization/receipt path. (Every change is `placeAnchor`, `moveAnchor`, or `removeAnchor` through `TabletopSession`, `LabLibrary.submit`, and `LabDataService` to `OperationService` as the app UI, with a receipt in the inspector. A removal is destructive, so it needs a grant issued for exactly that removal (`aRemovalNeedsAGrantForExactlyThatAnchorWhilePlacingAndMovingNeedNone`, `removingNeedsItsGrantAndItsUndoPutsTheObjectBack`); a model tool can only propose. Saving the table map is not a store operation: it writes ARKit's map file only after its consent dialog, and has not run.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Handheld AR, not headset passthrough or guaranteed persistent world tracking.

**Research:** [S40](../docs/SOURCE_INDEX.md#s40).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State claimed: implemented.** The virtual table, the declared fallback, ran in the Mac hosted tests and was drawn and driven in the iOS 27.0 simulator. The live ARKit adapter is compiled for the iOS device and simulator and has not run: a source build declares no `NSCameraUsageDescription`, so the route never offers the camera. Nothing is device-verified. The branch is `ticket/LAB-023-A`; integration is pending.

**What a person can do.** Open Tabletop Reality from its catalog page, the Mac sidebar, or View › Tabletop Reality (⌃⌘4). Orbit a drawn oak table; tap or click it to place the chosen object (six original procedural objects: Windmill, Lighthouse, Cottage, Pine Tree, Water Tower, Lantern), or use Place on Table for the free spot nearest the center, or Set Out Starter Scene. Select an object in the 3D view or the object list, then move it (5, 20, or 100 mm; ⌥ arrows on the Mac), turn it 15° (⌥[ and ⌥]), or remove it (⌘⌫). Clear Table asks first. Every change leaves a receipt with an undo in the inspector. Replay Tracking Loss plays a labeled 15-second recorded sequence that pauses and resumes placing and moving. Where the world-tracking probe allows it (a supported iPhone or iPad in a build that declares the camera purpose string), Start AR Camera asks for the camera and opens the live adapter: coaching to find a horizontal surface, a tap to place the table, objects at the same table-relative places, occlusion where supported, Keep Looking or Start Fresh after a stalled relocalization, Reset Table Position, and Save Map… behind a consent dialog.

**Decisions.**

- Lab-owned anchors are domain entities (`LabAnchor`), following LAB-004's session: a fixture key, a title, and a pose in whole millimeters and degrees in the table's own frame, always in the demo namespace. The spec's `WorldAnchor` was renamed so it never shadows visionOS ARKit's `WorldAnchor`.
- Poses are relative to the table, not the world, so the virtual table and AR show the same arrangement, and Start Fresh only places the table again.
- The only mapping data kept is ARKit's world map, written after the consent dialog to Application Support with complete protection, excluded from backup, never in the store or an export. Forget Saved Map deletes it. It is not a store operation.
- No purpose string was added. Qualifying the live adapter needs a build that declares `NSCameraUsageDescription` (the Store lane already merges `LAB_PURPOSE_CAMERA`, or a profile decision by the owner).

**Changed:**

- `Packages/LabDomain`: `Anchors.swift` (new: `LabAnchor`, `AnchorPose`, `FixtureKey`, `AnchorDraft`, `SpatialValidationError`); `EntityKind.anchor`, `AnchorID`, `EntityReference.anchor`; `placeAnchor`, `moveAnchor`, `removeAnchor` (destructive) and their planning, conflicts, and undo; Reset Demo removing every anchor ("cleared N placed objects"); anchor reads on `OperationStore`, `AuthorizedCommit.anchors`, the in-memory store, `OperationService.findAnchors`, `ReadTarget.anchors`, and `GrantTarget` fit. Tests: `AnchorTests` (10).
- `Packages/LabStore`: schema version 4 (`anchors`, demo namespace only, coordinates within ±5000 mm, yaw in 0…359) and its reads, upserts, preconditions, and removals. Tests: `AnchorStoreTests` (6); two migration tests expect version 4, and the newer-file test is relative to the current version.
- Test fakes that implement `OperationStore` gained the two anchor reads: `SpyStore` (LabDomain), `ContractStore` (LabStore), `CountingStore` (TypedIntelligence tests).
- `Packages/LabFeatures`: the `TabletopReality` product and target (new), depending on LabDomain and LabSupport, with `Resources/tabletop-kit.json`, and `TabletopRealityTests` (28 tests in 4 suites). LabCatalog tests expect seven implemented experiments.
- `Apps/Shared/TabletopReality/` (new): `TabletopSession`, `TabletopSceneController`, the views, the iPhone page and `TabletopLaunch`, and `LiveTabletop` (iOS only).
- `Apps/Mac/Window/TabletopColumns.swift` (new).
- Shared host hooks, one each: `SidebarDestination.tabletopReality` with its title and storage key and one `tabletop` session in `MainWindowState`; one case in each of `MainWindow`'s content, detail, and search-prompt switches; one sidebar row; View › Tabletop Reality (⌃⌘4) in `LabCommands`; `TabletopLaunch` in `ExperimentDetailView`; `LabDataService.anchors(as:)`; titles for the three kinds and the anchor entity in `ReceiptRecord`.
- At integration, Place on Table moved from ⌥⌘N to ⌃⌘N: the Lab menu already uses ⌥⌘N for Import Fixture Note (LAB-042).
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `TabletopReality`. Nothing else changed; regeneration is byte-identical. It was regenerated with XcodeGen on `command`, because research has none.
- `Config/ProductPolicy.txt`: RealityKit, RealityFoundation, and `_RealityKit_SwiftUI` for CoreLocal on macOS and iOS and for the SystemSurfaces host variant.
- `Tests/LabMacTests/TabletopHostTests.swift` (new, 6).
- `experiments/LAB-023-tabletop-reality.md`: `state: implemented`, the module split, and the implementation notes; the catalog JSON was regenerated.
- [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md): anchors and schema version 4. [VERIFICATION_BOUNDARIES](../docs/VERIFICATION_BOUNDARIES.md#realitykit-and-arkit-lab-023) and [S40](../docs/SOURCE_INDEX.md#s40): the installed SDK ledger. [BUILD_STATUS](../docs/BUILD_STATUS.md): the LAB-023-A rows.

**Implementation steps:**

1. **API gates.** The installed SDKs were read; findings are in the ledger and the spec's notes. Availability comes from the existing world-tracking capability report, never from a device name.
2. **Plane with coaching.** `ARWorldTrackingConfiguration` with horizontal plane detection and `ARCoachingOverlayView` (goal `.horizontalPlane`); compiled, not run.
3. **Original procedural objects.** The kit fixture: six objects of 3 to 6 primitives each in a fixed 12-color palette, under 8 KiB, strictly decoded.
4. **Mapping data with consent.** `MappingPolicy` allows a save only live, with a placed table, normal tracking, and a mapped or extending area, and only after the dialog; compiled, not run.
5. **Relocalization recovery.** `RelocalizationWatch` offers Keep Looking and Start Fresh after 20 seconds; tested with a manual clock and the replay.
6. **Deterministic tests.** The domain operations (`AnchorTests`, `AnchorStoreTests`, `TabletopOperationTests`), cancellation (`clearingStopsBetweenCommitsWhenCancelledAndKeepsWhatItFinished`), invalid input (`KitTests`, pose and key decoding, placement rules), and the unavailable path (the route tests and `theMacRoutesToTheVirtualTableAndSaysWhy`).

**Bug found and fixed in the simulator run:** the orbit target alone framed the table edge-on, so a tap never reached its top. The camera now starts above the front edge (2931a71).

**Evidence:** the LAB-023-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). Simulator screenshots were kept outside the repository.

**Not run:** the live AR adapter anywhere; a physical iPhone or iPad; the Mac window with a pointer or keyboard (only hosted tests); VoiceOver, Voice Control, and Full Keyboard Access passes; a 26-SDK compile.
