---
id: "LAB-012-A"
title: "Implement Point, Inspect, Propose"
status: "done"
milestone: "M3"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-007-B", "LAB-010-B"]
---

# LAB-012-A — Implement Point, Inspect, Propose

## Goal

Inspect an object or screenshot and turn observations into a reviewable lab record.

## Authority and scope

Read the [governing specification](../experiments/LAB-012-point-inspect-propose.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** point-inspect-propose module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Begin with a user-selected image
3. Run deterministic OCR/barcode where suitable
4. Offer a model-generated interpretation with image provenance
5. Add optional supported system visual-search participation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Barcode payloads cannot execute actions. (`BarcodeReading.canExecute` is fixed false. Payloads that look like links or shortcuts are stored as text in the item note, and the only domain operation is `createItem`: `aBarcodePayloadCannotBecomeAnAction`. Vision on a generated QR returned the payload as text: `aBarcodePayloadIsText`. Applying a record never runs the payload.)
- [x] Photos containing private text remain local by default. (`CaptureConsent.staysLocal` and `ImageEvidence.staysLocal` are fixed true. Visual search stays off until the person asks, and opting in still does not upload: `privateTextStaysOnDeviceUntilAPersonAppliesIt`. The module sources mention no network or cloud route: `sourcesHaveNoNetworkOrCloudRoute`. Nothing is written until Apply.)
- [x] Uncertain recognition stays an editable suggestion. (A line below the confidence floor is marked uncertain and stays editable; the person can replace the title and body before Apply: `anUncertainLineStaysAnEditableSuggestion`. System visual-search labels are always uncertain and do not commit: `systemLabelsStaySuggestionsAndDoNotRun`.)
- [x] Fallback is usable: Image picker plus OCR and manual fields.. (Optical recognition and typed fields both complete a record: `opticalRecognitionAndManualFieldsBothCompleteTheRecord`. An unavailable analyzer still allows the fields: `anUnavailableAnalyzerStillAllowsManualFields`. A model gate writes nothing, and the manual path still commits: `aModelFailureDoesNotWriteAndTheManualPathStillDoes`. The Mac host commits a typed record as the app UI: `PointInspectHostTests`.)
- [x] Sensitive operations share the domain authorization/receipt path. (Proposals run as `PointInspect.proposer` (model-tool). Apply creates the Inspections collection if needed and commits through `LabLibrary.submit` as the app UI. The proposer cannot commit: `theProposerCannotCommitTheRecord`. Hosted: `applyingATypedRecordCommitsAsTheAppUI`.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** System Visual Intelligence participation is not the same as arbitrary visual-agent control. Camera observation is not identity recognition.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06), [S55](../docs/SOURCE_INDEX.md#s55), [S62](../docs/SOURCE_INDEX.md#s62).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-012's spec now claims `implemented`. OCR of a drawn image and a typed record ran on the development Mac (research). Nothing here is device-verified. The system has not invoked the visual-search intent. The on-device image description path is compiled but was not executed in the default suite.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `PointInspect` product and target, and `PointInspectTests`.
- `Packages/LabFeatures/Sources/PointInspect/` (new):
  - `ImageEvidence`, `SelectedImage`, `CaptureConsent`, `InspectFailure`, and the image-model gate.
  - `Observation`, `BarcodeReading` (`canExecute` false), OCR lines, and suggestion sources.
  - `VisionImageAnalyzer`, `OnDeviceImageInterpreter` (27-generation `Attachment` from a `CGImage`, behind `compiler(>=6.4)`), scripted and unavailable inspectors.
  - `ReviewableInspection` / `ApprovedInspection`, `PointInspectBackend`, `ServicePointInspectBackend`, and `PointInspectFlow` with a time limit.
  - `VisualSearchParticipation`, `VisualSearchHandoff`, and `PointInspectVisualSearchIntent` (labels only).
- `Packages/LabFeatures/Tests/PointInspectTests/` (new): 16 tests in 4 suites.
- `Apps/Shared/PointInspect/` (new): `LibraryPointInspectBackend`, `PointInspectScreen`, list column, and catalog entry.
- Shared hooks, one case each:
  - `MainWindowState`: a `pointInspect` destination.
  - `SidebarView`: one row.
  - `MainWindow`: content and detail cases, and the search prompt.
  - `ExperimentDetailView`: one line for the entry.
  - `ActionAtlasHost`: includes `PointInspectIntentsPackage`.
  - `ActionAtlasHostTests`: the built-app metadata count is now 12 and expects `PointInspectVisualSearchIntent`.
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `PointInspect` and bundle the swatch. Watch and Apple TV do not.
- `Config/ProductPolicy.txt`: CoreLocal (macOS and iOS) and SystemSurfaces (iOS) may link Vision, ImageIO, CoreGraphics, VisualIntelligence, and Combine (Combine is pulled in by Vision / VisualIntelligence).
- `Fixtures/point-inspect/` (new): original 115-byte swatch PNG and README with its hash.
- `Tests/LabMacTests/PointInspectHostTests.swift` (new).
- `experiments/LAB-012-point-inspect-propose.md`: `state: implemented`, the module split, and implementation notes. The Fallback paragraph is unchanged. Catalog JSON regenerated.
- `docs/SOURCE_INDEX.md` (S55, S62), `docs/VERIFICATION_BOUNDARIES.md`, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**SDK symbols** (exact signatures in [S55](../docs/SOURCE_INDEX.md#s55), [S62](../docs/SOURCE_INDEX.md#s62), and the image-attachment row of [S06](../docs/SOURCE_INDEX.md#s06)). No new entitlement. No camera or photo-library purpose string. The Mac already has user-selected file access.

**Commands run:** listed in the LAB-012-A rows of [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run:**

- A physical iPhone or a camera capture.
- A live on-device image description (no live-model test in the default suite).
- System visual search listing or invoking the app.
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- A 26-family SDK compile.
- Manual presses through the Mac window.

**Known limitations:**

- The fixture PNG has no text; Vision proof used a drawn image and a generated QR in `VisionAdapterTests`.
- Visual Intelligence is weak-linked on the Mac; a macOS 26 process was not run.
- No View-menu shortcut was added, to avoid clashing with parallel branches. The sidebar row opens the experiment.
- Reset Demo does not remove Inspections (user namespace).

**Next dependency-ready ticket:** LAB-012-B (depends on this ticket, CORE-007, CORE-009, and CORE-010, all done).
