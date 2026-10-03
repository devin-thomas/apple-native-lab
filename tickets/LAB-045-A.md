---
id: "LAB-045-A"
title: "Implement Ink Has Structure"
status: "done"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B", "LAB-035-B"]
---

# LAB-045-A — Implement Ink Has Structure

## Goal

Annotate an object and keep the ink as editable data rather than flattening everything to a screenshot.

## Authority and scope

Read the [governing specification](../experiments/LAB-045-ink-has-structure.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** ink-has-structure module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Draw on original sample media
3. Persist editable ink with document IDs
4. Provide erase/undo and semantic text alternatives
5. Export flattened preview separately from native data
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Undo preserves anchoring after document resize. (`DocumentOperationTests.undoAfterResizeKeepsAnchoring`, `AnchorTests.resizeKeepsRelativePlacement`: strokes use unit-space anchors; after resize to 640×480, undo restores the empty layer while size stays 640×480, and a mid-document anchor still maps to the same relative place.)
- [x] Non-Pencil users complete the task. (`PreviewAndCapabilityTests.nonPencilPathsCompleteTheTaskAndAbsentGesturesStayAbsent`: Mac capability has no PencilKit canvas and still `canCompleteTask` via mouse/touch and typed notes; phone uses `drawingPolicy = .anyInput`. Package save path commits a typed-note annotation through `OperationService`.)
- [x] Unsupported pencil gestures are absent, not broken. (`InkCapability.defaultAbsentGestures` and the fixture list: squeeze, hover-only tool, and double-tap customization are not wired; the iPhone canvas does not attach a tool picker or Pencil interaction overrides.)
- [x] Fallback is usable: Mouse/touch annotations and typed notes.. (SwiftUI drag drawing on Mac and iPhone; typed notes on every host; `InkCapability.typedNotesOnly` still completes. Proven in package tests; Mac hosted UI walk is part of `script/test.sh`.)
- [x] Sensitive operations share the domain authorization/receipt path. (`SaveReceiptTests`: `InkSave.createOperation` / `updateNoteOperation` commit through `OperationService` with `GrantAuthorizationPolicy` as app UI; empty save refused before submit; duplicate document ID refused; receipt offers undo.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No iPad purchase required; advanced Pencil hardware features remain hardware-gated.

**Research:** [S53](../docs/SOURCE_INDEX.md#s53).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State claimed: implemented.** Domain and host surfaces are in this build. Package tests prove anchoring, undo-after-resize, save receipts, fallback capability, and absent Pencil gestures. Full `script/test.sh` is the automated gate. Nothing is device-verified; no person has used a real Apple Pencil or iPad.

**The task.** Open the fictional Harbor Chart (320×240), draw with pointer/touch (or PencilKit any-input on iPhone), type a note, undo/erase, optionally resize, export a flattened preview text separately, and Save Annotation through `LabLibrary.submit` as the app UI. Reset Demo clears only the experiment's working `InkDocumentStore`.

**Changed:**

- `Packages/LabFeatures/Package.swift`: `InkHasStructure` product/target and `InkHasStructureTests`.
- `Packages/LabFeatures/Sources/InkHasStructure/` (new): domain types, store, save planning, preview, capability.
- `Packages/LabFeatures/Tests/InkHasStructureTests/` (new): 15 tests in 4 suites.
- `Fixtures/ink/` (new): sample media and absent-gesture list.
- `Apps/Shared/InkHasStructure/` (new): session, canvas (SwiftUI + iOS PencilKit), workbench, page, catalog launch.
- `Apps/Mac/Window/InkHasStructureColumns.swift` (new).
- Shared hooks (one case each): `SidebarDestination.inkHasStructure`, `MainWindowState.ink`, `MainWindow` content/detail/search, `SidebarView` row, `LabCommands` View › Ink Has Structure (⌃⌥⌘2), `ExperimentDetailView` launch.
- `project.yml` + regenerated project: LabMac, LabPhone, LabPhoneSurfaces link `InkHasStructure`.
- `Config/ProductPolicy.txt`: CoreLocal and SystemSurfaces may link PencilKit on iOS.
- `experiments/LAB-045-ink-has-structure.md`: `state: implemented`, split, notes; catalog regenerated. Catalog tests expect 7 implemented / 41 specified.
- Installed SDK ledger and [S53](../docs/SOURCE_INDEX.md#s53); rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** PencilKit swiftinterfaces/headers on research: `PKDrawing` on Mac and iOS; `PKCanvasView` / `drawingPolicy` iOS-only.
2. **Sample media.** Harbor Chart fixture and `SampleMedia.harborChart`.
3. **Persist.** Document ID = item ID; extras hold native ink; note holds typed notes / stroke summary.
4. **Erase/undo and typed notes.** Domain operations plus session controls.
5. **Flattened preview.** `FlattenedPreview` labeled separate from editable ink.
6. **Tests.** Domain ops, cancellation message, invalid input, unavailable PencilKit path (Mac capability), save receipts.

**Not run:** Physical iPhone/iPad, real Apple Pencil, VoiceOver/Voice Control/Full Keyboard Access passes on this surface, 26-SDK compile.
