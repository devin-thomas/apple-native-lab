---
id: "LAB-004-A"
title: "Implement Surface Deck"
status: "done"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-004-A — Implement Surface Deck

## Goal

One reversible session state appears in a widget, a Control, and the main app.

## Authority and scope

Read the [governing specification](../experiments/LAB-004-surface-deck.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** surface-deck module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Build small/medium widgets from immutable snapshots
3. Expose one toggle and one launch action
4. Let users add Controls and map supported hardware triggers
5. Refresh by documented policy rather than a live polling timer
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Stale widget toggles reconcile to current state. (Every toggle carries the revision its surface showed. A stale revision gets a conflict receipt and nothing moves (`aStaleToggleGetsAConflictReceiptAndChangesNothing`, `aStaleControlGetsAConflictReceiptAndReconcilesToTheCurrentState`). The host then rewrites the snapshot and reloads the surfaces even when the file already held the current state (`aStaleControlChangesNothingAndItsSurfaceIsAskedToRedraw`). A toggle on the placeholder only shows the current state. In the iOS 27.0 simulator, the store held the session running at revision 13. A harness wrote an older snapshot (paused, revision 12) and reinstalled the app, which reloaded three widgets to that stale state. Tapping one launched the app in the background. The service recorded "Not applied because the demo session changed: expected revision 12, found 13.", the store stayed at revision 13, and all three widgets redrew as Running.)
- [x] Locked-device view redacts private labels. (Default path and in-app preview. By default the snapshot holds no label at all, only the state, revision, and write time (`aSnapshotIsRedactedByDefaultAndHoldsOnlyTheState`); the widget reads "Details hidden". Where and when the session last changed reaches a surface only after the person turns on Show Details on Widgets, and every surface marks that line `privacySensitive()`. In the simulator, with details on, the medium widget showed "Changed from Native Lab" and the deck's "Lock Screen, locked" preview, drawn with the privacy redaction, showed a placeholder bar in its place. A real locked device and a real Lock Screen widget were not driven.)
- [x] A denied update budget leaves a correct stale indicator. (Fixture path. Every timeline holds the snapshot now and the same snapshot marked "May be out of date" an hour later, and requests one refresh at that moment, so a declined refresh shows the stale entry (`aTimelineShowsTheSnapshotNowAndMarksItStaleIfTheNextRefreshNeverComes`, `aSnapshotNotConfirmedWithinTheWindowSaysItMayBeOutOfDate`). WidgetKit's budget cannot be denied in the simulator, and the hour was not waited out. A Control keeps its last value until reloaded and has no stale mark.)
- [x] Fallback is usable: Main-app state deck and static widget previews.. (CoreLocal, no extension, no App Group. On the Mac, View › Surface Deck (⌘7) showed the deck. Start, Pause, the receipt's Undo, and Reset Demo each changed the state with a receipt in the list and inspector. Reset Demo read "Reset the demo to its original 3 collections and 12 items: paused 1 session." In the iOS 27.0 simulator with `LabPhone-Core`, the deck opened from its catalog page and said "This build has no widget or Control". Pause and Undo moved the session from revision 13 to 14 to 15. The previews drew the small, medium, Lock Screen, locked Lock Screen, and Control views from the same snapshot, labeled "Preview". The hosted Mac tests cover the same path (`theCoreLocalMacHasNoSurfacesAndTheDeckStillWorks`).)
- [x] Sensitive operations share the domain authorization/receipt path. (Every change is `DomainOperation.setSession` through `SessionActions`, `LabLibrary.submit`, and `LabDataService` to `OperationService`: as App UI from the deck, as App Intent from the Control, the widget, and Shortcuts. Receipts from both land in the same list (`theDeckAndTheIntentChangeOneStateWithReceiptsInOneList`). Starting or pausing is not destructive and needs no grant. A model tool can read and propose but never commit it, and a share extension is refused without a grant (`SessionTests`), so ADR-011 and ADR-013 are unchanged.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Widget/Control availability is per platform. An iPhone Action button does not imply a Watch Action button.

**Research:** [S01](../docs/SOURCE_INDEX.md#s01), [S59](../docs/SOURCE_INDEX.md#s59).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

LAB-004's spec now claims `implemented`. The deck ran on the Mac and in the iOS simulator in both CoreLocal and SystemSurfaces builds, and the widget and both Controls ran in the iOS simulator. Nothing is device-verified.

**The session state, and why.** The state is a demo "session: running or paused" flag, `LabSession`, changed only by `DomainOperation.setSession(id:expected:running:)`.

- It is small, holds nothing a person wrote, and each change has an exact inverse, so the receipt's undo always works.
- It is not destructive, so a Control can change it without a confirmation dialog or an ADR-013 grant. The ADR-011 ceilings still apply: a model tool can only propose, and a share extension or peer needs a grant.
- No existing operation fitted. Archiving a sample is destructive. A flag on a collection or an item would have shown up in the collection lists and counts, and user rows can never be deleted.
- It lives in the demo namespace. Reset Demo pauses a running session at its next revision instead of removing it, so a toggle prepared before a reset conflicts instead of applying.

**Where the pieces live.**

- `Packages/LabDomain`:
  - `LabSession`, `SessionID`, and `EntityReference.session`.
  - `setSession` and its planning: creation, conflict, no-change, and undo.
  - `OperationService.findSession`.
  - The session reads on `OperationStore`, and the session writes in `AuthorizedCommit` and the in-memory store.
  - Reset Demo pausing sessions, and `GrantTarget` for a session.
- `Packages/LabStore`: schema version 3, a `sessions` table that only allows the demo namespace, and its reads, upserts, and revision checks.
- `Packages/LabFeatures/Sources/SurfaceDeck/` (new target and product). It depends on LabDomain only and imports SwiftUI and AppIntents, never WidgetKit:
  - `SessionActions`, shared by the deck and the intents, and the `SessionBackend` a host provides.
  - The intents: `SetDemoSessionIntent`, a `SetValueIntent` and, on iOS, a `LiveActivityIntent`; `GetDemoSessionIntent`; and `OpenSurfaceDeckIntent`, an `OpenIntent`.
  - `SessionSnapshot` and `SessionSnapshotFile`.
  - `SurfacePresentation` and `SessionTimeline`.
  - The widget and Control views.
- `Extensions/SurfaceWidgets/` (new, SystemSurfaces):
  - The Demo Session widget: small, medium, and Lock Screen rectangular.
  - The Demo Session Control toggle and the Open Surface Deck Control button.
  - Its Info.plist and entitlements. It reads the snapshot file in the App Group and nothing else.
- `Apps/Shared/SurfaceDeck/` (new):
  - `SurfaceDeckModel`.
  - `SurfaceDeckHost`, which registers the intents' backend and refreshes the snapshot as receipts arrive.
  - `LibrarySessionBackend` and `SnapshotPublisher`. The WidgetKit reloads compile only in a SystemSurfaces build.
  - The deck, its previews, the catalog-page entry, and the iPhone presenter for the launch action.
- `Apps/Mac/Window/SurfaceDeckColumns.swift` (new): the deck and its previews in the Mac window.
- Shared host files, one hook each:
  - `LabMacApp` and `LabPhoneApp`: `SurfaceDeckHost.connect`. On iPhone, also `surfaceDeckPresenter()`.
  - `ExperimentDetailView`: `SurfaceDeckLaunch`.
  - `MainWindowState`: `.surfaceDeck`. `MainWindow` shows its columns and follows the launch action. `SidebarView` lists it. `LabCommands` adds View › Surface Deck (⌘7).
  - `ActionAtlasHost`: the intents package.
  - `LabDataService`: one `session(_:as:)` read.
  - `ReceiptRecord`: titles for the new kind and entity.
- `project.yml` and the regenerated project:
  - LabMac and LabPhone link `SurfaceDeck`.
  - New target `SurfaceWidgets`, embedded only by `LabPhoneSurfaces` and built by `LabPhone-Surfaces`.
- `Config/ProductPolicy.txt`: `link SystemSurfaces ios WidgetKit` and `link SystemSurfaces ios _AppIntents_SwiftUI` (the overlay behind the widget's `Toggle(isOn:intent:)`), and updated comments on the AppIntents and CryptoKit lines. `Config/Profiles/SystemSurfaces.xcconfig`: the attached targets.

**Changed.** Everything listed above. In addition:

- Tests:
  - `Packages/LabDomain/Tests/LabDomainTests/SessionTests.swift` (9).
  - `Packages/LabStore/Tests/LabStoreTests/SessionStoreTests.swift` (5).
  - `Packages/LabFeatures/Tests/SurfaceDeckTests/` (27 in 5 suites).
  - `Tests/LabMacTests/SurfaceDeckHostTests.swift` (7 hosted).
- `Tests/LabMacTests/ActionAtlasHostTests.swift`: the metadata test now expects the three Surface Deck intents beside Action Atlas's eight, with nothing else.
- Test fakes that implement `OperationStore` gained the two session reads: `SpyStore` in LabDomain, `ContractStore` in LabStore, and `CountingStore` in the TypedIntelligence tests. Two LabStore migration tests now expect version 3.
- Catalog: `experiments/LAB-004-surface-deck.md` (`state: implemented`, module split, implementation notes) and the regenerated catalog JSON. The catalog tests now expect 5 implemented, 43 specified, and M1 at 5 of 6.
- `docs/SHORTCUTS_AND_INTENTS.md`: the session intents. `docs/BUILD_STATUS.md`: the scheme row and evidence rows.

**Evidence:** the LAB-004-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md).

- The simulator runs used a throwaway UI-test harness in a copy of this branch, which is not committed.
- They ran on a new iPhone 17 Pro simulator on iOS 27.0, which was shut down and deleted afterwards.
- The Mac runs used a Debug build under a separate bundle prefix, so the app's own container was not touched. They were driven through the Accessibility API by process ID.
- Screenshots were kept outside the repository.

**Blocked, not failed:** the widget, the Controls, and the App Group snapshot on a device. A free Personal Team cannot sign App Groups, so `LabPhone-Surfaces` cannot be installed on the owner's iPhone. The CoreLocal deck and its previews need no App Group and are the device path today.

**Not run:**

- Any physical device. Only the integrator installs to devices.
- A real Lock Screen widget and a locked device.
- A denied WidgetKit budget, and the hour to the stale entry.
- The Action button and hardware triggers.
- A Mac or Watch widget, neither of which is built.
- VoiceOver speech, iPad layouts, a 26-SDK compile, and the Store lane manifest.

**Known limitations:**

- A Control's value is cached until it is reloaded. After the snapshot file was deleted, existing widgets and a newly added one kept the cached state until the app was reinstalled.
- `SetDemoSessionIntent` conforms to `LiveActivityIntent` only so that iOS runs it in the app's process; see the experiment's implementation notes.
- Receipts are listed for the app session only, as in CORE-005. Where and when the last change was made is kept in the app's defaults.
- A Reset Demo, or an undo from the receipt inspector, credits the change to Native Lab.
- The launch action crashed the app in four early simulator runs, on a missing environment object in the presented deck. After the library was passed into the sheet, 6 runs from a clean install passed. Which build the last crashing run used is uncertain, so LAB-004-B should repeat the launch action from a clean install.

**Next dependency-ready ticket:** LAB-004-B (qualification). It needs this ticket, and CORE-007, CORE-009, and CORE-010, all done.

**Integration (2026-09-30):** merged after LAB-008-A. The SQLite store keeps both LAB-008's item `extras` column and this branch's `sessions` table (schema version 3). Surface Deck keeps Command-7 and Portable Objects Command-8. The `LabPhoneSurfaces` host variant had lost its PortableObjects dependency to a duplicated `product:` key during successive merges; it is restored, the share extension's own ShareIngress dependency is kept, and the variant now bundles the intelligence fixture notes like `LabPhone`. With this merge all six M1 experiments are implemented.
