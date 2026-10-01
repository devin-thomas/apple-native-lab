---
id: "LAB-016-A"
title: "Implement Pick Up Here"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-016-A — Implement Pick Up Here

## Goal

Move a draft to another device and resume at the exact selected section without pretending Handoff is file sync.

## Authority and scope

Read the [governing specification](../experiments/LAB-016-pick-up-here.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** pick-up-here module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Advertise a small resumable activity
3. Transfer only identifiers and position
4. Resolve or request the underlying document
5. Handle a newer revision on the destination
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Missing document prompts import instead of empty success. (`ResumeTests.aMissingDocumentPromptsImportInsteadOfSucceeding`: resume returns `.needsImport`, `revealedText` is empty, the sentence asks to import, the store stays empty. `FallbackTests.handoffCanStayOffAndTheCopiedDocumentStillImports`: a destination with only the link gets the same prompt before the document is imported.)
- [x] Revoked access does not reveal old content. (`ResumeTests.revokedAccessDoesNotReadOrRevealTheDraft`, `preparingARevokedDraftReturnsNoDocument`, `anActorWithoutReadPermissionRevealsNothing`: access is refused before the item is read; `revealedText` and the sentence carry none of the sentinel section or title.)
- [x] A changed document clamps the saved position safely. (`ResumeTests.aShorterNewerDraftClampsTheSavedPosition`: after a shorter update, section 1 lands on 0, `clamped` and `newerRevision` are true, the removed section is gone. `aNewerDraftKeepsAPositionThatStillExists` keeps section 1 when the note is unchanged.)
- [x] Fallback is usable: Copy an explicit continuation link or document.. (`FallbackTests.theActivityAndLinkCarryOnlyTheIdentifierAndPosition`, `handoffCanStayOffAndTheCopiedDocumentStillImports`, `importingAgainDoesNotDuplicateTheDraft`: the link and activity carry three fields; with Handoff off, the copied document imports through `OperationService` as the app UI and resumes at the saved section. The Mac and iPhone UI expose Copy Continuation Link, Copy Document, Continue from Link, and Import Document.)
- [x] Sensitive operations share the domain authorization/receipt path. (`FallbackTests.aModelToolCannotImport` refuses a model-tool commit and writes nothing. A successful import's receipt is `createItem` admitted as `.appUI`. The host's `LibraryPickUpBackend` commits through `LabLibrary.submit` as the app UI.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Handoff is a continuation hint, not guaranteed bulk transfer or instant background execution.

**Research:** [S60](../docs/SOURCE_INDEX.md#s60).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-016's spec now claims `implemented`. Package tests prove the domain contract and the copied-document fallback. No two-device Handoff was run. Nothing here is device-verified.

**Changed:**

- `Packages/LabFeatures`:
  - The `PickUpHere` product and target (new), depending on LabDomain. It holds `DocumentLocator`, `SectionPosition`, `ContinuationToken`, `DraftText`, `ContinuationPayload`, `ContinuationLink`, `ContinuationDocument`, `ContinuationOffer`, `HandoffActivity`, `PickUpResolver`, `ContinuationImporter`, `ServicePickUpBackend`, `PickUpError`, and `SampleDraft`.
  - `PickUpHereTests` (new): `ResumeTests` and `FallbackTests` (17 tests).
  - `LabCatalogTests` now expect seven implemented experiments.
- `Apps/Shared/PickUpHere/` (new): `PickUpSession`, `LibraryPickUpBackend`, the shared actions and screens, and `pickUpContinuation`.
- `Apps/Mac/Window/PickUpColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState` has the destination and the per-window session.
  - `MainWindow` has the columns, the search prompt, and `.pickUpContinuation`.
  - `SidebarView` has the row.
  - `LabCommands` has View › Pick Up Here (⌥⌘1).
  - `ExperimentModuleAction` (in `PortableObjectsViews.swift`) has the Open Pick Up Here button.
  - `LabPhoneApp` holds a session, continues activities, and does not add a tab.
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `PickUpHere` and list `nativelab.pick-up-here` under `NSUserActivityTypes`. No new entitlement.
- `Fixtures/LAB-016/` (new): the original three-section draft and a README (SHA-256 `1943d54e…`).
- `docs/DATA_CONTRACTS.md`: continuation hints.
- `docs/SOURCE_INDEX.md` (S60): installed-SDK check.
- `experiments/LAB-016-pick-up-here.md`: `state: implemented`, the implemented split, and implementation notes. The Fallback paragraph is unchanged. The catalog JSON was regenerated.
- This record, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** The installed Foundation header was read for `NSUserActivity` on the macOS, iOS, watchOS, and tvOS 27.0 SDKs. Findings are in the spec's implementation notes and S60. No `LAB_SDK_27` gate and no entitlement.
2. **Advertise.** `HandoffActivity` builds an `NSUserActivity` of type `nativelab.pick-up-here` with the three-field payload, Handoff on or off, and search, public indexing, webpage URL, and continuation streams off. The hosts list the type.
3. **Transfer only identifiers and position.** The activity and `nativelab://continue` link carry `documentID`, `revision`, and `section`. An extra key is refused whole.
4. **Resolve or request.** `PickUpResolver.resume` returns `.needsImport` when the lab has no item, after an access check. The UI asks for the pasted document.
5. **Newer revision.** A shorter destination draft clamps the section into range and reports the clamp; a still-valid section keeps its index and notes the newer revision.
6. **Tests.** Domain resume and import, cancellation (`cancellationReadsNothing`), invalid input (negative section, smuggled payload, hostile documents), and the unavailable path (`anUnavailableStoreDoesNotResume`).

**Not run:**

- A physical device.
- Two-device Handoff delivery.
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- A 26-SDK compile.
- Opening `nativelab://continue` as a system URL (the fallback is copy and paste inside the app).

**Known limitations:**

- On iPhone, a continued activity updates the shared session but does not navigate to the Pick Up Here screen by itself; open it from the catalog page to see the result.
- Clear Continuation drops the in-memory hint only. The sample draft is ordinary user data once imported; Reset Demo does not remove it.
- No two-device Team ID delivery was proven.

**Next dependency-ready ticket:** LAB-016-B (depends on this ticket, CORE-007, CORE-009, and CORE-010).
