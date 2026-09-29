---
id: "LAB-001-A"
title: "Implement Action Atlas"
status: "done"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008"]
---

# LAB-001-A — Implement Action Atlas

## Goal

Create a collection, find an item, mutate it, and inspect the same receipt from three entry points.

## Authority and scope

Read the [governing specification](../experiments/LAB-001-action-atlas.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** action-atlas module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Seed 12 original sample objects with stable UUIDs
3. Expose create/find/update/archive/export intents
4. Call the same operation from UI and Shortcuts
5. Show typed output and undo receipt
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Duplicate request IDs cause one mutation. (Every change carries one request ID, and a creation derives its new entity's ID from it, so a retry repeats the same operation and gets the recorded receipt back. `aDuplicateRequestIDCommitsOnce` runs create collection, create item, and archive twice each from both entry points: one entity, one revision step, identical receipts. `aRepeatedIntentRequestCommitsOnceAndIsListedOnce` does the same through the host's SQLite store and lists the receipt once. A shortcut can pass its own request ID; reusing one for a different change is refused with a readable sentence.)
- [x] Missing and ambiguous entities produce recoverable errors. (A missing item or collection is a sentence that says to find it again, and an entity query leaves a missing identifier out. With no collection named, Create Lab Item uses your only collection, asks through `requestDisambiguation(among:dialog:)` when you have several, and without a chooser refuses as ambiguous; with none it says to create one first. Text that matches several items returns them all, so the system asks which one. Fixture tests in `ActionAtlasSafetyTests` and `ActionAtlasIntentTests`. The system's own disambiguation dialog was not observed.)
- [x] UI and intent yield identical persisted state. (`uiAndIntentYieldIdenticalPersistedState`, a hosted Mac test: the same seven changes, one find, and one export, once through the action browser's app-UI path and once through the App Intents, each on a fresh SQLite store with the same request IDs. Every collection and item compares equal, and so does each receipt's operation, status, changes, removals, summary, and undo, and the export bytes. Excluded by design: operation IDs, the receipt's adapter (App UI or App Intent), and the first-run Reset Demo receipt, whose request ID is random.)
- [x] Fallback is usable: A normal app action browser runs without Siri or Apple Intelligence.. (Mac: all eight actions run from Action Atlas, reached from the sidebar or View › Action Atlas ⌘4, with each receipt opening in the receipt inspector. iPhone 18 Pro simulator, iOS 27.0: the Actions tab created a collection, archived a demo sample, opened its receipt, and undid it. Neither run used Siri, Shortcuts, or Apple Intelligence.)
- [x] Sensitive operations share the domain authorization/receipt path. (Every intent and every browser action calls `ActionAtlasActions`, then `LabLibrary.submit`, then `LabDataService.perform`, then `OperationService.perform`, as the App Intent or app-UI actor. An intent's archive gets its ADR-013 grant only from an `IntentConfirmation`, which exists only after the system confirmation returns and covers only that operation. Without one the host refuses (`theHostRefusesAnIntentArchiveWithoutTheSystemConfirmation`); a confirmation for a different item is refused too.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** AppEntity is not arbitrary access to other apps. Domain operations remain authorization-checked.

**Research:** [S01](../docs/SOURCE_INDEX.md#s01), [S03](../docs/SOURCE_INDEX.md#s03), [S05](../docs/SOURCE_INDEX.md#s05).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

Status is left for the program record. LAB-001's spec now claims `implemented`, because its fallback ran on the Mac and in the iOS simulator. Nothing here is device-verified.

**Where the intents live.** They live in a new `ActionAtlas` target in `Packages/LabFeatures`, because App Intents in a package work in this SDK. A probe in a throwaway copy showed Xcode 27.0 running `appintentsmetadataprocessor` on the package target and merging its intent and entity into `NativeLab.app/Contents/Resources/Metadata.appintents`, in Debug and Release, once the host declared an `AppIntentsPackage` that includes the package's. Conforming the `App` type itself does not compile under Swift 6, so the host uses a separate struct. The host glue and the in-app browser are in `Apps/Shared/ActionAtlas/`.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `ActionAtlas` product and target, the `ActionAtlasTests` target, and a dependency on LabDomain.
- `Packages/LabFeatures/Sources/ActionAtlas/` (new):
  - `ActionAtlasActions` is the one action library both entry points call.
  - `ActionAtlasBackend`, `AtlasEntryPoint`, `AtlasAuthority`, and `IntentConfirmation` connect it to the host.
  - `AtlasRequest` handles request IDs and the entity IDs derived from them.
  - `ActionAtlasError` holds the readable errors, and `PortableLabItem` is the export format.
  - The entities and queries, and eight intents: Create Lab Collection, Create Lab Item, Find Lab Items, Get Lab Item, Update Lab Item, Archive Lab Item, Restore Lab Item, and Export Lab Item.
- `Packages/LabFeatures/Tests/ActionAtlasTests/` (new).
- `Apps/Shared/ActionAtlas/` (new): `ActionAtlasHost` (the host `AppIntentsPackage`, dependency registration, and `LibraryAtlasBackend`), `AtlasAction`, `AtlasRun`, and `AtlasActionForms`.
- `Apps/Shared/Library/LabDataService.swift` (additive):
  - `CommitAuthority.intent(IntentConfirmation?)`. Each authority selects its actor, `appUI` or the new `appIntent`.
  - An intent gets a grant only for a confirmation that covers the exact operation.
  - Pass-through reads, and a collection list that takes identifiers from the store and reads each collection through the service.
- `Apps/Shared/Library/LabLibrary.swift` (additive): `openedService()` and `submit(_:requestID:authority:names:)`, which record other adapters' receipts in the session list the inspector reads. Receipt recording moved into one private helper.
- `Apps/Mac/`: `LabMacApp` registers the backend at launch. There is an Action Atlas sidebar destination with its columns (`Window/ActionAtlasColumns.swift`, new) and the command View › Action Atlas (⌘4).
- `Apps/Phone/`: `LabPhoneApp` registers the backend at launch and gains an Actions tab (`Tabs/ActionsTab.swift`, new).
- `project.yml` and the regenerated project: LabMac and LabPhone link the `ActionAtlas` product. Nothing else changed, and regeneration is byte-identical.
- `Config/ProductPolicy.txt`: CoreLocal may link AppIntents and CoreTransferable (the browser's Share button) on macOS and iOS. No entitlement was added.
- `experiments/LAB-001-action-atlas.md`: `state: implemented`, the actual module split, and implementation notes. The Fallback paragraph is unchanged.
- The catalog JSON was regenerated. `ExperimentCatalogTests` and `ExperimentRegistryTests` now expect one implemented experiment.
- `Tests/LabMacTests/ActionAtlasHostTests.swift` (new), and this record plus rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Required behavior:**

1. **Seed.** Reuses the 12 samples in `Fixtures/demo/seed.json`. No second seed exists.
2. **Intents.** Create, find, get, update, archive, restore, and export, over `LabItemEntity` and `LabCollectionEntity`:
   - Both entities have `EntityStringQuery` queries, and Create Lab Item's collection picker offers only your own collections.
   - Every intent reads and commits as the App Intent actor (`AdapterKind.appIntent`) through the host's `OperationService`.
   - Create makes user-namespace entities.
   - Export returns an `IntentFile` holding a versioned `native-lab-item` JSON document, or plain text. It carries the item's own fields and its collection's identity, never receipts, request IDs, or store metadata.
3. **Same path.** Stated in the acceptance criteria above.
4. **Grants.** `ArchiveItemIntent` calls `requestConfirmation(conditions:actionName:dialog:)` with a custom destructive Archive/Cancel. Only its return creates the `IntentConfirmation` the host turns into a 30-second grant for that operation, which is revoked after the commit. `CommitAuthority` was extended; no second grant path was added.
5. **Typed output and receipts.** Each intent returns its entity, the found entities, or the export file, with the receipt's sentence as its dialog. The intent's receipt joins the session list, so the Mac inspector and the iPhone receipt views show it with its undo offer.
6. **Recoverable errors.** Stated in the acceptance criteria above.
7. **Idempotency.** Stated in the acceptance criteria above.
8. **Fallback.** Stated in the acceptance criteria above.
9. **Deterministic tests.** `ActionAtlasOperationTests`, `ActionAtlasSafetyTests`, and `ActionAtlasIntentTests` in the package, and `ActionAtlasHostTests` in the Mac host. They cover:
   - each operation from both entry points;
   - a declined confirmation, a declined choice, and a cancelled task, each committing nothing;
   - invalid titles, notes, changes, limits, search text, and request IDs;
   - the unavailable path, both with no connected host and with a store that cannot open.

**ADR-012 and the experience.** The demo-collection rule did not make the experience wrong. It adds one step to a first run: a new item needs a collection of your own, so you create one first, and the error for a demo collection says so. Editing, archiving, and exporting samples need no extra step. On the Mac, the in-app Create Lab Item form offered only your own collection; the intent's collection picker was not opened in Shortcuts.

**Evidence:** the LAB-001-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). Screenshots were kept outside the repository.

**Not run:**

- Siri and any physical device.
- The Mac Shortcuts app. The only library there is a real person's, so it was not opened, and no CLI lists an app's actions (`shortcuts` only runs, lists, views, and signs shortcuts).
- AppIntentsTesting system-path tests, which need a signing team.
- VoiceOver speech, iPad layouts, and a 26-SDK compile.
- The system disambiguation dialog.

**Known limitations:**

- Receipts are kept for the session only, as in CORE-005. An intent that runs while the app is not running records its receipt in the store, but the inspector shows it only if the same process stays open.
- `OperationService` has no collection list, so `LabDataService` reads identifiers from the store and each collection through the service.
- No curated App Shortcuts were declared; the actions appear in Shortcuts as the atomic library.
- The sandboxed Mac app logs that it could not register with the intents framework (`com.apple.linkd.autoShortcut`, NSCocoaErrorDomain 4097). A build of another branch with no App Intents logs the same line. Its effect on Mac Shortcuts is not known.

**Next dependency-ready ticket:** LAB-001-B (qualification). It needs this ticket, CORE-007 (done), and CORE-009 and CORE-010, which are both still planned. Every other LAB-nnn-A ticket, including LAB-002-A, LAB-004-A, LAB-007-A, LAB-008-A, LAB-010-A, and LAB-035-A, waits on LAB-001-B.
