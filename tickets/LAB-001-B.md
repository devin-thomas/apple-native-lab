---
id: "LAB-001-B"
title: "Qualify and document Action Atlas"
status: "done"
milestone: "M1"
kind: "qualification"
depends_on: ["LAB-001-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-001-B — Qualify and document Action Atlas

## Goal

Prove Action Atlas on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-001-action-atlas.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** action-atlas tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Duplicate request IDs cause one mutation; Missing and ambiguous entities produce recoverable errors; UI and intent yield identical persisted state
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Duplicate request IDs cause one mutation. (LAB-001-A: `aDuplicateRequestIDCommitsOnce`, `aRequestIDMakesAnIntentRetrySafe`, and, in the Mac host, `aRepeatedIntentRequestCommitsOnceAndIsListedOnce`. Added here: the same request ID from the other entry point is refused and commits nothing, in the package (`aRequestIDFromTheOtherEntryPointIsRefused`, both directions) and in the host (`aRequestIDFromTheOtherEntryPointIsRefusedInTheHost`). A late retry of a creation returns the first receipt and leaves later edits in place (`aLateRetryOfACreateDoesNotRevertLaterChanges`). A refused, declined, or cancelled request records nothing, and the same request later commits exactly once (`aDeniedIntentArchiveCommitsOnceWhenConfirmedUnderTheSameRequest`, `aDeclinedArchiveCanBeConfirmedLaterUnderTheSameRequest`, `aCancelledTaskCanBeRetriedUnderTheSameRequest`, and `aDeclinedIntentConfirmationLeavesNoReceiptInTheStoreOrTheSession` in the host.) Fixture path.)
- [x] Missing and ambiguous entities produce recoverable errors. (LAB-001-A: `aMissingItemIsARecoverableError`, `aMissingCollectionIsARecoverableError`, `aNewItemNeedsACollectionOfYourOwn`, `severalCollectionsOfYourOwnAreAmbiguousUntilOneIsChosen`, `textThatMatchesSeveralItemsReturnsThemAllForTheSystemToDisambiguate`, `aStoredItemThatNoLongerExistsFailsReadably`, and `createItemAsksWhichCollectionWhenYouHaveSeveral`. Added here: two of your collections with the same title stay distinct, and creating an item without naming one is refused as ambiguous until one is chosen (`sameTitledCollectionsStayDistinctAndMakeTheChoiceAmbiguous`). A demo collection refuses the Create Lab Item intent (`theCreateItemIntentCannotAddToADemoCollection`). An update to an archived item is refused with a sentence that says to restore it first (`anArchivedItemRefusesAnUpdateFromAnySnapshot`). The chooser is a stand-in: the system's disambiguation dialog has not been observed.)
- [x] UI and intent yield identical persisted state. (LAB-001-A: `uiAndIntentYieldIdenticalPersistedState`, a Mac hosted test. Added here: the complete showcase interaction, 8 changes and 8 reads including a second Reset Demo, leaves identical state from both entry points. It runs through the Action Atlas actions and the App Intent types in the package (`bothEntryPointsReplayTheShowcaseToIdenticalPersistedState`), and in the Mac host on SQLite (`theShowcaseInteractionLeavesIdenticalStateFromBothEntryPoints`, which writes the evidence record `action-atlas-host-ui-and-intent.json`). In `Packages/LabDemo`, the same script replayed as the App Intent adapter ends in the app-UI replay's state (`theAppIntentAdapterReachesTheSameStateWithReceiptsNamingIt`). Fixture path.)
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations. (Four records in `evidence/LAB-001/`. The three fixture records are at source revision 6b1ba97, with Xcode 27.0 (27A266a) and the macOS 27.0 SDK. The two LabDemo records carry the SHA-256 of the exact script and seed bytes, the adapter (`app-ui`, `app-intent`), the store, the timebase, and the replay fingerprint. The host record's toolchain is read from the built app's Info.plist; it carries the seed's SHA-256 and every request ID, and names both entry points. The physical iPhone record's toolchain is read from the Info.plist of the installed e4fe012 build (iphoneos27.0); it carries the seed's SHA-256 and the hashes of the private store copy, and names the `app-ui` adapter. Each lists what it doesn't cover. `evidence-records` validates all four.)
- [x] The walkthrough never claims a simulation is the live integration. ([`docs/walkthroughs/LAB-001-action-atlas.md`](../docs/walkthroughs/LAB-001-action-atlas.md) opens with what is real and what is simulated: the in-app path is verified on a physical iPhone, and the Shortcuts path in the simulator only. It names the live integration, Shortcuts or Siri on a device, as not yet shown, calls the replay a simulation of the logic, and labels every screenshot "iOS Simulator … not a device".)
- [x] Only approved original/public-safe material enters screenshots and exports. (The exporter's tier review ran on both kept exports. The showcase export held 9 artifacts, all `public-fixture` and approved, with none refused and no override. The device export held 1 record, classed `user-private` because it comes from the owner's iPhone, and included only by a recorded override: it carries aggregates and file hashes, never content. The 3 screenshots are frames of the app's own window in a simulator created for this ticket and deleted afterwards. They show only the original demo content and what the test typed, with the status bar fixed at 9:41. They were reduced to 460 × 1000, and their EXIF and XMP chunks were removed.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac; Watch adapter later.

**Unavailable path:** A normal app action browser runs without Siri or Apple Intelligence.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**State: LAB-001 stays `implemented`.** The in-app path is verified on a physical iPhone; the Shortcuts path is verified in the simulator only. The iPhone record supports `device-verified` for the in-app action browser through `DeviceProof`. Action Atlas's primary adapter is App Intents, though, and no device run has exercised it, so the experiment is not promoted.

**The one run that would promote it.** On the physical iPhone, run Archive Lab Item from the Shortcuts app on a demo sample and confirm in the system dialog. Then a read-only copy of the app's store must show a new committed receipt with adapter `app-intent` for that archive, offering a Restore undo. The app lists receipts only for the session that made them, so the store copy is the check. Record it with `DeviceRunEvidence` (`Packages/LabDemo`), with the device class, OS, build, and profile expiry, and have the run reviewed before the state changes.

**Changed:**

- The two self-tests in `script/validate/tests/test_evidence.py` that assumed an empty `evidence/` now clear it in their temporary copy. Two new ones check a new record beside the stored ones, and the stored records themselves. With one record present, the old tests failed 2 of 91 and the new ones pass 93 of 93.
- New `Fixtures/showcase/action-atlas/`: `script.json`, 19 steps, and `seed.json`, a byte-for-byte copy of `Fixtures/demo/seed.json`. `Fixtures/showcase/README.md` describes it.
- New tests:
  - `Packages/LabDemo/Tests/LabDemoTests/ActionAtlasShowcaseTests.swift`: 7 tests and the evidence export.
  - `Packages/LabDemo/Tests/LabDemoTests/DeviceRunEvidenceTests.swift`: the device-run record generator and its check.
  - `Packages/LabFeatures/Tests/ActionAtlasTests/ActionAtlasQualificationTests.swift`: 11 tests, 13 cases.
  - `Packages/LabFeatures/Tests/ActionAtlasTests/ActionAtlasShowcaseReplayTests.swift`: 2 tests.
  - `Tests/LabMacTests/ActionAtlasQualificationHostTests.swift`: 4 tests.
  - `Tests/LabMacTests/ActionAtlasHostEvidenceTests.swift`: 1 test, which attaches its record.
  - `Tests/LabMacTests/ActionAtlasAccessibilityTests.swift`: 5 tests, 17 cases, one known issue.
- New `evidence/LAB-001/`: 4 records.
- New `docs/walkthroughs/LAB-001-action-atlas.md` and 3 screenshots in `docs/walkthroughs/images/`.
- `docs/ACCESSIBILITY_REVIEW.md`: two automated-check rows, the Action Atlas flows A1 to A5 with their manual matrix (all `not-run`), and the Action Atlas review with 6 findings.
- `docs/VERIFICATION_BOUNDARIES.md`: an installed SDK ledger for the App Intents symbols. `docs/SOURCE_INDEX.md`: installed SDK notes under S01, S03, and S05.
- `docs/BUILD_STATUS.md`: the LAB-001-B rows.

`Apps/`, `project.yml`, `Config/`, `script/test.sh`, `.github/`, and the experiment spec are unchanged. The experiment's `state` stays `implemented`.

**Evidence records** (`evidence/LAB-001/`):

| Record | Path | What it proves |
|---|---|---|
| `action-atlas-showcase-app-ui.json` | fixture | The complete fixture interaction passes from a clean SQLite store through `OperationService` as the app-UI adapter: 19 of 19 steps. Two replays share fingerprint `4e814ad8…`. Script and seed hashes are recorded. |
| `action-atlas-showcase-app-intent.json` | fixture | The same script submitted as the App Intent adapter passes, 19 of 19. Two replays share fingerprint `ecfafb33…`, and the final state equals the app-UI replay's. No intent type ran. |
| `action-atlas-host-ui-and-intent.json` | fixture | In the sandboxed Mac app, the action browser's path and the App Intent types, run with the showcase's request IDs on fresh SQLite stores, leave identical collections, items, and receipts. 69 of 69 comparisons matched, and the toolchain was read from the app bundle. |
| `action-atlas-iphone-in-app.json` | physical, iPhone17,1 (iPhone 16 Pro), iOS 27.0 (24A5430a), profile expires 2026-10-06 | The in-app action browser works on a physical iPhone, run by the owner and corroborated by the device store's receipts: 6, all committed, all `app-ui`. It supports `device-verified` for the in-app path only; the reads are owner-reported, and there is no screen recording. |

**Replay determinism.** The export test ran twice, in separate processes, at 6b1ba97. Each run replayed the showcase twice as each adapter, so there were 8 SQLite replays. Every app-UI replay had fingerprint `4e814ad8dc3e5eab14d0fc86176847e1e9b5194be235675181e0b16eb230cc4b`, and every App Intent replay had `ecfafb33cc1609091eb116a61c901788750d1b17e9be8ecc69498648adc2ac9f`. In `ActionAtlasShowcaseTests`, an in-memory replay and one on the suspending clock matched the app-UI fingerprint too.

**Tier review.** The showcase export had 4 runs, 3 records, the script, and the seed. The review approved all 9 as `public-fixture`, refused none, and needed no override; its summary led with "Passed". The device export had 1 record, classed `user-private` and included by a recorded override: aggregates only. Both export folders were kept outside the repository. The result bundles' own manifests name the Mac's hardware identifier, so only the records were taken from them.

**Step 3, by case:**

| Case | Tests (package unless marked) |
|---|---|
| Denial | `anIntentCannotArchiveWithoutTheConfirmation` and `aConfirmationCoversOnlyTheChangeThatWasConfirmed` (LAB-001-A); `aDeniedIntentArchiveCommitsOnceWhenConfirmedUnderTheSameRequest`, `aRequestIDFromTheOtherEntryPointIsRefused`, `theCreateItemIntentCannotAddToADemoCollection`; host: `theHostRefusesAnIntentArchiveWithoutTheSystemConfirmation` (LAB-001-A), `aRequestIDFromTheOtherEntryPointIsRefusedInTheHost`; replay: `withoutTheApprovalTheArchiveIsRefused` |
| Cancellation | `decliningTheConfirmationCommitsNothing`, `aCancelledTaskStopsBeforeTheCommit`, and `decliningToChooseACollectionCommitsNothing` (LAB-001-A); `aDeclinedArchiveCanBeConfirmedLaterUnderTheSameRequest`, `aCancelledTaskCanBeRetriedUnderTheSameRequest`; host: `aDeclinedIntentConfirmationLeavesNoReceiptInTheStoreOrTheSession`; replay: `aCancelledReplayCommitsNothingAfterTheCancel` |
| Stale state | `aStaleRevisionRecordsAConflictAndOverwritesNothing` (LAB-001-A); `aStaleSnapshotCannotArchiveAndRecordsAConflict`, `aStaleUndoOfferIsAConflictNotARevert`, `anArchivedItemRefusesAnUpdateFromAnySnapshot`; host: `aStaleIntentSnapshotConflictsAndTheInspectorShowsIt` |
| Duplicate state | `aDuplicateRequestIDCommitsOnce` (LAB-001-A); `aLateRetryOfACreateDoesNotRevertLaterChanges`, `sameTitledCollectionsStayDistinctAndMakeTheChoiceAmbiguous` |
| Reset without touching imported user data | `resetDemoLeavesImportedAndIntentCreatedDataUntouched`; host: `resetDemoLeavesIntentCreatedAndImportedDataUntouched`, where a second connection to the same SQLite file adopts the import as the share extension will; replay: the showcase's second Reset Demo |

**Step 5 review:**

- **Accessibility.** The Action Atlas screens were checked against [ACCESSIBILITY_REVIEW](../docs/ACCESSIBILITY_REVIEW.md#action-atlas-review-lab-001-b) with automated checks and static review only. There are 6 open findings. The largest: the forms post no announcement (rule 4), and at the largest text size on iPhone no form's action button is on screen without scrolling (rule 6). The manual rows for flows A1 to A5 are `not-run`.
- **Rights.** The new fixture is original and synthetic under the MIT License: its seed is the app's own demo seed. The screenshots show only the app and its original demo content. No Apple artwork or third-party material was added ([ASSET_POLICY](../docs/ASSET_POLICY.md)).
- **Privacy.** The hosted tests use fresh stores in the app container's temporary folder, never the app's real store. The Mac's Shortcuts library was not opened. The device store copy stays private: the record carries only aggregates and hashes. No evidence file, screenshot, or commit holds a serial number, device identifier, account, name, or local path ([SECURITY_AND_PRIVACY](../docs/SECURITY_AND_PRIVACY.md)).
- **Source and availability.** The App Intents symbols LAB-001-A compiled are now in the [installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md#installed-sdk-ledger), read from the Xcode 27.0 macOS and iOS SDK interfaces. `AppIntentsTesting` ships with Xcode 27.0 for every platform from the 27.0 OS releases, but has not run.
- **Capability descriptor.** LAB-001's registration and fallback sentence are unchanged and still accurate. No Readiness capability describes Shortcuts or Siri availability; that is a request below.

**Commands run** (all exit 0 unless noted):

- `python3 script/validate/all.py`: 8 of 8 passed, with 0, 3, and then 4 records.
- `python3 -B -m unittest discover -s script/validate/tests`: 93 passed with 0, 1 (a temporary probe), 3, and 4 records. Before the fix, with 1 record: 2 of 91 failed.
- `swift test --package-path Packages/LabFeatures`: LabCatalog 14; ActionAtlas 49 in 5 suites.
- `swift test --package-path Packages/LabDemo`: 70 in 11 suites, one of them skipped unless a device run is named.
- `xcodebuild … -scheme LabMac-Core -destination 'platform=macOS' test` (in `script/test.sh`): 53 tests in 11 suites. 52 passed, and 1 is an expected failure, the known issue.
- `script/test.sh`: passed before the first commit, and again on the final tree with the 4 records stored.
- `xcodebuild … -only-testing:LabMacTests/ActionAtlasHostEvidenceTests -resultBundlePath <bundle> LAB_SOURCE_REVISION=6b1ba97 test`, then `xcrun xcresulttool export attachments`.
- `LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=6b1ba97 LAB_SDK_NAME=macosx27.0 LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a LAB_HOST_EVIDENCE_RECORD=<record> swift test --package-path Packages/LabDemo --filter ActionAtlasShowcaseEvidence`, twice.
- `LAB_DEVICE_RUN_FACTS=<facts> LAB_DEMO_EVIDENCE_DIR=<folder> swift test --package-path Packages/LabDemo --filter DeviceRunEvidence`.
- The iPhone UI-test harness, in a throwaway copy with a UI-test target that is not committed, on a simulator created for it and then shut down and deleted. `xcodebuild … -scheme LabPhone-Core -destination 'platform=iOS Simulator,id=<new device>' test`: the third run passed both tests. The first two failed on the harness's own queries.
- SDK reads: `grep` of `AppIntents.swiftinterface` in the macOS and iOS 27.0 SDKs, and a check of the `AppIntentsTesting.framework` folders.

**Not run:**

- Shortcuts on the physical iPhone, and so the App Intent adapter on any device. The device store holds no `app-intent` receipt. This is the gate for `device-verified`.
- Siri, on any device.
- The Mac Shortcuts app: its library belongs to a person.
- The system's disambiguation dialog.
- AppIntentsTesting: the source says it needs a signing team, and it needs a test target.
- VoiceOver, Voice Control, and Full Keyboard Access, by a person: all flow rows are `not-run`.
- The Mac accessibility audit: UI automation asks for authentication on this Mac.
- iPad, Watch, and a 26-family SDK compile.

**Requests for other owners:**

- Action browser views (`Apps/Shared/ActionAtlas/`): findings 1 to 5 in the accessibility review. Post the receipt's announcement after each change; pin each form's action on iPhone; read item rows with commas; label the Find Items text field.
- Readiness capabilities (`Packages/LabSupport`): consider a capability for Shortcuts and Siri availability, so the Readiness screen can state that path.
- Build configuration (`project.yml`): a UI-test target for `LabPhone-Core` would make the iPhone journey and audit a committed, repeatable check instead of a throwaway harness.
- Build status: the header's "Last updated" line and the "Not run" row on device verification can now mention the in-app iPhone record.

**Next dependency-ready tickets.** With this ticket done, these have every dependency met: LAB-004-A, LAB-007-A, LAB-008-A, LAB-010-A, and LAB-035-A for the rest of M1, and LAB-002-A, LAB-019-A, LAB-023-A, LAB-037-A, LAB-040-A, and LAB-041-A beyond it. CORE-012 still waits on the other M1 -B tickets.
