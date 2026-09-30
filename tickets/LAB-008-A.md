---
id: "LAB-008-A"
title: "Implement Portable Objects"
status: "done"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-008-A — Implement Portable Objects

## Goal

Drag a rich lab object into another window or export it as a inspectable document.

## Authority and scope

Read the [governing specification](../experiments/LAB-008-portable-objects.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** portable-objects module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Provide native document, JSON, text, and URL representations where meaningful
3. Show an export preview with fields and destination
4. Validate imports before committing
5. Preserve unknown fields in a versioned extras map
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Unicode and empty optional fields round-trip. (The document is kept as a lossless tree. Strings keep their exact scalars, and `null`, absent, `""`, `0`, and `0.0` stay distinct: `DocumentCodecTests`. Through the store, `ImportTests.aDocumentSurvivesTheStoreOnEitherSide` exports, imports into a fresh lab, and exports again, with 5 note and extras shapes, giving the same bytes. The hosted `aRoundTripThroughTwoSQLiteStoresReturnsTheSameDocument` does the same through two SQLite stores. The bundled sample has a combining accent, CJK, an emoji, an empty note, extras, and an unknown field. On the Mac it went through the app's SQLite store and out through Export… as 682 bytes, SHA-256 `4dfbd2a9…`, identical to the sample. The iPhone simulator's export to Files matched those bytes.)
- [x] A path-traversal attachment is rejected. (`StagedPath` rules apply to every attachment path: `DocumentCodecTests.unsafeAttachmentsAreRefused` and `Fixtures/LAB-008/traversal-attachment.anlab`. On the Mac, Import from File… showed "Attachment 1 has a path that points outside the object (it contains “..”), so the object was refused. Nothing was imported." Staging and the store were unchanged.)
- [x] Reimporting one document does not duplicate stable items. (Identity decides: `documentID` is the item ID. A reimport with the same title and note plans nothing, and one that differs changes only when the person applies it, as one update with an undo. A retry replays its receipt, because the request ID derives from the content digest: `ImportTests.reimportingTheSameDocumentNeverDuplicatesTheObject`. On the Mac: a drag between windows, the file dialog, and a drag from Finder each showed "Already in this lab" or "This lab's copy is different", and the store held one user item. In the iPhone simulator, reimporting from Files showed "Already in this lab".)
- [x] Fallback is usable: File picker and explicit export preserve the full native document.. (Mac: Export… saved the byte-identical document, and Import from File… read it back. Both need `com.apple.security.files.user-selected.read-write`, which was added with the evidence below. iPhone simulator: Export… saved to On My iPhone. After the app was uninstalled, a fresh store imported that file from Files under its stable ID, with a receipt.)
- [x] Sensitive operations share the domain authorization/receipt path. (Every import is staged by `LabStaging`, validated, and committed only as one `createItem` or `updateItem` through `LabLibrary.submit`, `LabDataService.perform`, and `OperationService.perform`, as the app UI. Its receipt joins the session's receipts, and nothing writes the store directly. Every refusal leaves the store unchanged: `ImportTests` snapshots, the hosted tests' receipt counts, and the Mac store read after the manual run, which held 12 demo items, 1 user item, and 4 app-UI receipts.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Transfer representations are adapters, not automatic clipboard parity on every platform.

**Research:** [S11](../docs/SOURCE_INDEX.md#s11), [S12](../docs/SOURCE_INDEX.md#s12).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

LAB-008's spec now claims `implemented`. Its drag between Mac windows and its fallback ran on the Mac, and its Files round trip ran in the iOS simulator. Nothing here is device-verified.

**Document format.** `native-lab-object`, `schemaVersion` 1, with the fields, canonical form, type, item mapping, and import rules recorded in [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#portable-documents). The file extension is `.anlab`, and the type is `<bundle prefix>.nativelab.object`, conforming to `public.json`.

**Changed:**

- `Packages/LabDomain`:
  - `ItemExtras` (new) is the item metadata this build does not interpret.
  - `LabItem.extras` and `ItemDraft.extras` carry it: a creation sets it, and every later revision, including a Reset Demo restore, keeps it. Both encode it only when it is present, so receipts without it keep their shape; LabDemo's recorded fingerprints still match.
  - The in-memory store keeps a stored item's extras on upsert.
  - Tests: `ItemExtrasTests` (new).
- `Packages/LabStore/Sources/LabStore/SQLiteOperationStore.swift` writes `extras` when an item's row is inserted and reads it back; an update never names it. Tests: `ItemExtrasStoreTests` (new).
- `Packages/LabFeatures`:
  - The `PortableObjects` product and target (new), depending on LabDomain and LabStaging, with the bundled sample as a resource. It holds `PortableValue`, `LabDocument`, `DocumentMapping`, `ImportPlan`, `PortableObjectsImporter`, `PortableObjectsBackend`, `ServiceBackend`, the `Transferable` types, `RepresentationDescriptor`, `ExportPreview`, and `PortableObjectError`.
  - `PortableObjectsTests` (new): `DocumentCodecTests`, `ImportTests`, and `TransferTests`.
  - `LabCatalogTests` now expect two implemented experiments.
- `Apps/Shared/PortableObjects/` (new): `PortableObjectsSession`, `LibraryPortableBackend`, and the shared views.
- `Apps/Mac/Window/PortableObjectsColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState` has the destination and the per-window session.
  - `MainWindow` has the columns, the search prompt, and the catalog page's open action.
  - `SidebarView` has the row.
  - `LabCommands` has View › Portable Objects (⌘5).
  - `ExperimentDetailView` has the Open Portable Objects button and the module's "How this works" text.
  - `LabDataService` has a read-only receipt lookup for import retries.
- `project.yml` and the regenerated project, byte-identical over two runs:
  - LabMac and LabPhone link `PortableObjects`.
  - Both declare `UTExportedTypeDeclarations` and `LabObjectTypeIdentifier`.
  - LabMac gains `com.apple.security.files.user-selected.read-write`.
  - No `CFBundleDocumentTypes`: the app does not open documents from Finder or Files by itself. Import from File…, drops, and Export… are the path.
- `Config/ProductPolicy.txt`: CoreLocal on macOS may carry that entitlement. CoreLocal on macOS and iOS may link CoreFoundation, whose URL resource-key constants LabStaging and the drop checks use, now that a host links LabStaging. The first release manifest failed without that line.
- `Tests/LabMacTests`: `PortableObjectsHostTests` and `PortableObjectsAccessibilityTests` (new). `AccessibilityTree` exposes its root for the second.
- `Fixtures/LAB-008/` (new): hostile documents and their README.
- `docs/DATA_CONTRACTS.md`: the portable-document details and item extras.
- `experiments/LAB-008-portable-objects.md`: `state: implemented`, the implemented split, and implementation notes. The Fallback paragraph is unchanged. The catalog JSON was regenerated.
- This record, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** The installed SDK was read for `Transferable` (`exported(as:)`, `init(importing:contentType:)`, `FileRepresentation`, `suggestedFileName`), `UTType(exportedAs:conformingTo:)`, `dropDestination(for:isEnabled:action:)`, `onDropSessionUpdated` (iOS 27, so not used), and the Transferable `fileExporter`. The findings are in the spec's implementation notes.
2. **Representations.** Native document (a file and data), JSON (the same bytes), and plain text (a labeled summary). No URL is offered, and the preview says why.
3. **Export preview.** It shows every field, each representation and what it keeps, the destination ("a file you choose"), the file name, and the document's text with its size.
4. **Validate before committing.** Every import is staged, then checked again from disk, decoded with every schema rule, planned, and verified once more at commit.
5. **Unknown fields.** They stay in the item's versioned extras entry and return on export.
6. **Tests.** The domain operation, cancellation (`aCancelledImportCommitsNothing`), invalid input (the codec refusals and hostile fixtures), and the unavailable path (`withoutAStoreAnImportSaysTheLabIsUnavailable`, a hosted test: a store that cannot open makes an import say the lab is unavailable, and nothing is staged or recorded).

**Bugs found and fixed in the manual runs:**

- On the Mac, a custom `accessibilityLabel` on selectable text crashed the app with a stack overflow when an outside assistive client read it. The label is gone. The live app was walked element by element from outside before and after the fix; the hosted harness cannot take that path.
- On iPhone:
  - Two buttons in one list row both fired: Export… opened the share sheet. Each control now has its own row.
  - A row's first tap did nothing, because value links were mixed with the catalog page's destination link. The screen now uses destination links only.
- The Mac catalog button read the window through `@FocusedValue`, which is `nil` inside the window. It now uses an environment action.

**Not run:**

- A physical device.
- iPad drag and multiwindow; there is no iPad.
- A person's own drag to Finder. The synthetic drag was refused by Finder's paste-location sandbox extension (`-20`), as the spec's notes record.
- A drag into apps other than TextEdit and Finder.
- A drop from another app on iPhone.
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- `.anlabpack` and attachment storage; there is no attachment entity.
- A 26-SDK compile.

**Integration (2026-09-29):** merged after LAB-007-A, LAB-010-A, and LAB-035-A. Portable Objects moved to Command-8 (Command-5 and Command-6 were taken; Command-7 is reserved for Surface Deck). The base `link * * CoreFoundation` policy line already covers LabStaging, so this branch's CoreLocal CoreFoundation lines were dropped; its file-dialog entitlement stays. The `LabPhoneSurfaces` host variant links PortableObjects. The declared-type host test now checks that the app's type is among those registered for `.anlab`, because other builds on the same Mac can register the extension too.
