---
id: "LAB-010-A"
title: "Implement Typed Local Intelligence"
status: "done"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-010-A — Implement Typed Local Intelligence

## Goal

Turn an ambiguous note into a typed proposal, then let a deterministic operation perform the approved change.

## Authority and scope

Read the [governing specification](../experiments/LAB-010-typed-local-intelligence.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** typed-local-intelligence module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Probe model readiness and language support
3. Generate a constrained draft from a bundled text fixture
4. Validate lengths, values, and cross-field rules
5. Preview the diff before commit
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Model-unavailable paths remain usable.
  - `TypedIntelligenceViewTests` renders the real view inside the Mac app with a fake device where Apple Intelligence is off:
    - It shows the probe's own sentence, "Service: Apple Intelligence is turned off (SystemLanguageModel.default.availability reports .appleIntelligenceNotEnabled)".
    - The model button is disabled.
    - Through accessibility presses alone, it drafts with the sample parser and applies the change, leaving an app-UI receipt.
  - `ModelReadinessTests` names the closed gate for device-not-eligible (hardware), Apple Intelligence off (service), model not ready (asset), and an unsupported locale (service), and treats an unmeasured model as unknown, never ready.
  - The extractor checks availability again for every request (`theModelIsCheckedAgainForEveryRequest`), and a failed draft proposes nothing (`aFailedDraftProposesNothing`).
  - No real device with the model unavailable was available: this Mac and the iOS 27.0 simulator both report it available.
- [x] Malicious imported instructions cannot authorize tools.
  - The session's tool list is fixed in code: one read-only `findSamples`. Everything before approval runs as the model-tool adapter, whose ceiling is read and propose.
  - `everythingBeforeApprovalRunsAsTheModelTool`: a scripted model follows the injected note into seven lookups. Every authorized access came from the model tool, and none was a commit.
  - The proposer cannot commit, even when code tries (`theProposerCannotCommitEvenWhenCodeTries`). The host has no commit authority that maps to it (`theHostHasNoCommitPathForTheProposer`).
  - Extra JSON fields cannot widen a draft (`extraFieldsCannotWidenTheDraft`).
  - The injected fixture yields at most one update proposal (`theInjectedNoteCanOnlyEverProposeOneEdit`).
  - The live model on the injected note proposed only the kraft card's observation, called no tool, and wrote nothing.
- [x] Generated-but-invalid values never reach persistence. A counting store shows zero writes in each of these cases:
  - Seven hostile drafts (`hostileOutputIsBlockedAndNeverWrites`): instructions followed, a sample addressed by UUID, a near-miss title, 10,000-character fields, control characters, empty fields, and no change.
  - Eight malformed or cut-off JSON answers (`malformedOutputNeverBecomesADraft`).
  - Seven model failures.
  - A valid proposal that was never approved (`aValidProposalChangesNothingUntilAPersonApprovesIt`).
  - A proposal made before the sample changed elsewhere: it cannot be approved, and an earlier approval commits only a conflict receipt (`aProposalForAChangedSampleIsNotApprovedAndNeverOverwrites`).
  - The validator's length, value, and cross-field rules are in `ProposalValidationTests`.
- [x] Fallback is usable: Deterministic sample parser and manual editor clearly labeled as non-model paths..
  - Each draft carries a source badge, "Sample parser (not a model)" or "Manual editor (not a model)", and each button's hint says "Not a model".
  - Both complete the flow: draft, edit, apply, receipt.
    - In the package: `theParserPathCompletesTheInteraction` and `theManualEditorCompletesTheInteraction`.
    - In the Mac host: `theWorkbenchCompletesTheFallbackWithoutTheModel`.
    - In the rendered view: the accessibility test above.
  - The package suite, including both fallback tests, also passed on the iOS 27.0 simulator. The iPhone screens were not driven there (see Not run).
- [x] Sensitive operations share the domain authorization/receipt path.
  - Apply calls `LabLibrary.submit`, which calls `LabDataService.perform`, then `OperationService.perform`, as the app UI under the approval's new request ID. The receipt joins the session list the inspector reads (`proposingRunsAsTheModelToolAndApplyingAsTheAppUI`).
  - A proposal can only be one `.updateItem` on an offered demo sample (`onlyAnUpdateToAnOfferedSampleCanComeOut`). That change is not destructive, so no grant is involved.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Structured generation constrains form, not factual truth. No hidden network fallback or billing.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

LAB-010's spec now claims `implemented`. The model path ran on the development Mac, and the fallback ran on the Mac and in the iOS 27.0 simulator. Nothing here is device-verified.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `TypedIntelligence` product and target, and the `TypedIntelligenceTests` target. It depends on LabDomain and LabSupport.
- `Packages/LabFeatures/Sources/TypedIntelligence/` (new):
  - `ExtractionProposal`, `ValidationIssue`, `EvidenceSpan`, and `ProposalValidator`.
  - Two extractors: `OnDeviceModelExtractor`, which uses Foundation Models with the `findSamples` tool, and the non-model `SampleParser`.
  - The read-only `SampleLookup` tool, and `ModelReadiness` over the CORE-004 probe.
  - The review gate (`ReviewableProposal`, `ApprovedChange`), `TypedIntelligenceFlow`, and `TimeLimit`.
- `Packages/LabFeatures/Tests/TypedIntelligenceTests/` (new): 57 tests in 8 suites. `LiveModelTests` is opt-in.
- `Apps/Shared/Intelligence/` (new):
  - `LibraryIntelligenceBackend`, and a metadata-only `DiagnosticsLog` to the system log.
  - `IntelligenceWorkbench`, `TypedIntelligenceView`, the note list, the Mac columns, and the catalog-page entry.
- Shared hooks, one case each:
  - `MainWindowState`: a `typedIntelligence` destination and `intelligenceNote`.
  - `SidebarView`: one row.
  - `MainWindow`: the content and detail cases, the search prompt, and `.environment(window)`, so the catalog page can open the destination.
  - `ExperimentDetailView`: one line for the entry.
  - `LabDataService`: a `propose(_:as:)` pass-through.
  - iPhone gets no tab.
- `project.yml` and the regenerated project: LabMac and LabPhone link `TypedIntelligence` and bundle the two notes. Nothing else changed.
- No new framework or entitlement. `Config/ProductPolicy.txt` already allows FoundationModels for CoreLocal on macOS and iOS.
- `Fixtures/intelligence/` (new): two original notes and a README with their hashes.
- `Tests/LabMacTests/TypedIntelligenceHostTests.swift` and `TypedIntelligenceViewTests.swift` (new).
- `experiments/LAB-010-typed-local-intelligence.md`: `state: implemented`, the module split, and implementation notes. The Fallback paragraph is unchanged.
- The regenerated catalog JSON. `ExperimentCatalogTests` and `ExperimentRegistryTests` now expect two implemented experiments.
- `docs/SOURCE_INDEX.md` (S06, with notes on S07 and S09), and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**SDK symbols** (the exact signatures are in [S06](../docs/SOURCE_INDEX.md#s06)). Nothing needs an entitlement: the model ran inside the sandboxed Mac app, whose only entitlement is App Sandbox.

- 26.0 on iOS, macOS, and visionOS:
  - `SystemLanguageModel.default`, with `availability` and `supportsLocale(_:)`.
  - `LanguageModelSession(model:tools:instructions:)`, which is also available on watchOS from 27.0.
  - `respond(to:schema:includeSchemaInPrompt:options:)`, with `GenerationSchema(type:description:properties:)` and `.anyOf`.
  - `@Generable`, `@Guide`, `GeneratedContent(json:)`, and `isComplete`.
  - `Tool`, which is also available on watchOS from 27.0.
  - `GenerationOptions(samplingMode: .greedy, maximumResponseTokens:)`.
- 27.0, compiled only under `#if compiler(>=6.4)` and read behind `if #available`:
  - `SystemLanguageModel.variant`, for evidence only.
  - The 27 error types `LanguageModelError`, `SystemLanguageModel.Error`, `GeneratedContent.ParsingError`, and `LanguageModelSession.Error`.
- The app targets need no `LAB_SDK_27` guard: they call no 27-only symbol directly.
- `PrivateCloudComputeLanguageModel` (27.0) is in the SDK and never referenced.

**Real model runs** on the development Mac (Apple M5 Max, macOS 27.0, en_US). The model read `availability == .available`, `supportsLocale()` true, variant "AFM 3 Core Advanced", and `contextSize` 8192. Each fixture was drafted twice with greedy sampling over the 12 demo samples, and the store saw no writes.

| Where | Ambiguous note | Injected note |
|---|---|---|
| `swift test` process on macOS (`LAB_LIVE_MODEL=1`) | Verdigris swatch both times, title kept, adding the note's first sentence. Evidence: "the blue one bled through the vellum again" and "stayed tacky for hours". 3 `findSamples` calls. 4,137 and 3,411 ms | Kraft card, adding "corners fray after a week in the drawer. Still takes pencil well." 0 calls. 1,633 and 1,641 ms |
| Sandboxed Mac app, hosted test through the workbench, then Apply | The draft was approvable and was applied as the app UI, 3.6 s for the whole test. The test does not assert which sample; a second, rendered run in the same app showed Verdigris swatch. | not run |
| iOS 27.0 simulator on this Mac, package tests | Cobalt swatch both times, same added sentence. 1 call. 3,321 and 2,779 ms | Kraft card, same as the Mac. 1,589 and 1,572 ms |

Limitations of these runs:

- The model's choice of sample differs between processes on the same Mac, while each process repeated its own choice.
- Neither environment used the note's quoted rename, and on the Mac the model listed no other possible samples. That is why the validator now shows every sample the note names outright ("The note also names Tracing vellum, Cobalt swatch, and Amber swatch").
- The timings are single runs, not a benchmark.
- A simulator run is not device evidence.

**Commands run:** listed in the LAB-010-A rows of [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run:**

- A physical iPhone.
- A device where the model is really unavailable.
- The iPhone screens in the simulator: the request for simulator control was not answered, so the app was installed, launched, and screenshotted only.
- The model path pressed through the Mac window by hand.
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- A 26-family SDK compile.
- The M1 compatibility Mac.

**Known limitations:**

- The proposal's title limit (60 characters) and added-note limit (280) are the experiment's, and tighter than the domain's.
- Receipts are kept for the session only, as in CORE-005.
- The experiment's diagnostics log has no in-app viewer yet.
- No View-menu shortcut was added, to avoid clashing with parallel branches.

**Next dependency-ready ticket:** LAB-010-B, which needs this ticket, CORE-007, CORE-009, and CORE-010 (all done). LAB-011-A, LAB-012-A, LAB-015-A, and LAB-006-A wait on LAB-010-B.
