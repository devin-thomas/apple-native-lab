---
id: "LAB-032-A"
title: "Implement Render That Survives"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-032-A — Implement Render That Survives

## Goal

Start a render, leave the screen, return, and see a truthful recoverable job instead of a vanished spinner.

## Authority and scope

Read the [governing specification](../experiments/LAB-032-render-that-survives.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** render-that-survives module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Validate file access and destination capacity
3. Create a durable foreground job
4. Use continued processing only when qualified
5. Checkpoint, cancel, and atomically publish output
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Cancellation never replaces a good output with a partial file. (A finished movie is published only by one `rename(2)` of a checked file, and a stop is honored only before it. `RenderRunTests.cancellingAtAnyPointKeepsTheGoodOutputByteForByte` cancels at 5 points, from the first frame to just before publishing, and the previous movie keeps its bytes with nothing else left; `aCancelledFirstRenderLeavesNoOutputAtAll` and `aJobCancelledByAnotherWriterStopsWithoutPublishing` cover a first render and a cancel from elsewhere. In the iPhone simulator harness, a cancel while running left the published digest `acbe92ea2fa4bebc…` unchanged.)
- [x] Task expiration produces a resumable or clearly failed job. (An ended runway stops the worker at its next frame and records `interrupted(expired)` with finished segments kept: `anExpiredRunwayStopsAtACheckpointAndTheJobResumesToTheSameMovie`, through a test runway. A failure is `failed` with a sentence. In the simulator, iOS refused continued processing ("unavailable"), so the expiration of a real system task was not observed; the same stop path ran for leaving the foreground (2 of 9 saved, resumed to a checked movie) and for a force-quit (`app-stopped`, then cancelled).)
- [x] GPU-unavailable uses a supported lower-cost path. (The CPU painter draws the same bytes as the GPU painter (`FrameTests`). With no Metal device every frame took the CPU path, and when the GPU stopped being allowed mid-run the remaining frames did (`withoutAGPU…`, `aGPUThatMayNotBeUsedNowFallsBackPerFrame`). On iPhone the app never uses the GPU in the background. The Mac app drew all 48 frames on the GPU in the hosted test.)
- [x] Fallback is usable: Keep the job foreground; Mac worker only while explicitly running.. (iPhone simulator: the foreground job stopped at a checkpoint on leaving and resumed to a published movie whose digest matched its record. Mac: the hosted tests ran the worker in the sandboxed app, and a job left running by an earlier process read as stopped after launch. A person's own quit on the Mac was not run by hand.)
- [x] Sensitive operations share the domain authorization/receipt path. (Every job step is `startJob` or `updateJob` through `LibraryJobBackend`, `LabLibrary.submit`, `LabDataService.perform`, and `OperationService.perform` as the app UI, with a receipt in the session's list: the hosted test reads Start Job, 4 checkpoints, and Finish Job there. A model tool can propose a job change but not commit one (`JobTests`, `JobRecorderTests`). Publishing a file to the experiment's own folder is part of the job the person started; nothing is written outside it.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Background APIs do not promise completion, launch at arbitrary times, or infinite agent execution.

**Research:** [S28](../docs/SOURCE_INDEX.md#s28), [S41](../docs/SOURCE_INDEX.md#s41).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State claimed: implemented.** Renders ran as jobs in package tests on the Mac, in the sandboxed Mac app (hosted tests), and in the iPhone app in an iOS 27.0 simulator, where iOS answered the continued-processing request with "unavailable", so the foreground fallback is what ran. Nothing is device-verified. The branch is `ticket/LAB-032-A`; integration is pending.

**The job model, for this lab and the ones that reuse it.** A job is LabDomain state, `LabJob`, stored with its receipts (schema version 4). `startJob` and `updateJob` (checkpoint, interrupt, resume, cancel, fail, succeed) are the only changes, each through `OperationService` with a receipt, never destructive and never undoable. Progress only moves forward and may have no total, which Live Session Beacon (LAB-005) can show as indeterminate. `LabJobs` is the reusable runtime: `JobRecorder`, `JobRecovery`, `JobStopSignal`, `DestinationCheck`, `AtomicPublication`, and the `JobRunway` protocol. Object Forge (LAB-025) and Capture With Consent (LAB-033) need only a new `JobKind` and their own worker. The contract and its corrections to the planned states are in [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#jobs-and-progress).

**What a person can do.** Open Render That Survives (Mac: sidebar or View › Render That Survives, ⌘9; iPhone: the experiment's catalog page). Choose the short fixture or the long one, which renders at playback speed for about 24 seconds. Render, then Pause, Resume, or Cancel. Leave the app, quit it, or force it to stop: on return the job reads running, or stopped with its reason and its saved steps, with Resume and Cancel. The published movie plays in the app with its size and SHA-256, and says which finished job recorded that digest. Every step is a receipt in the inspector.

**Changed:**

- `Packages/LabDomain`: `Jobs.swift` (new: `JobKind`, `JobProgress`, `JobInterruption`, `JobFailure`, `JobOutput`, `JobPhase`, `LabJob`, `JobDraft`, `JobTransition`), `JobID` and `EntityReference.job`, the two operations and their planning, Reset Demo removing demo jobs (counted apart from samples), `findJob` and `findJobs`, the store reads and the commit's `jobs`, the in-memory store, new `ValidationError` and `RuleViolation` cases, and the grant target. Tests: `JobTests` (12, new); the test store gained the two reads.
- `Packages/LabStore`: schema version 4 (`jobs`, with namespace, kind, and user-row triggers), job reads and upserts, and `SQLiteValue.null`. Tests: `JobStoreTests` (7, new); three expectations moved from version 3 to 4.
- `Packages/LabFeatures`: the `LabJobs` and `RenderThatSurvives` products and targets (new), `LabJobsTests` (11) and `RenderThatSurvivesTests` (23), and the bundled `recipes.json`. `ActionAtlasError` and the TypedIntelligence test store cover the new cases. The catalog tests now expect 7 implemented and 41 specified.
- `Packages/LabDemo`: `DemoRunner` describes the three new rule violations.
- `Apps/Shared/RenderSurvives/` (new): `LibraryJobBackend`, `RenderStudioModel`, and the views. `Apps/Mac/Window/RenderColumns.swift` (new). `Apps/Phone/Jobs/ContinuedProcessingRunway.swift` (new).
- Hooks in shared host files, one case each: `SidebarDestination.renderSurvives` with its title and storage key; `MainWindow`'s content and detail switches; one sidebar row; View › Render That Survives (⌘9); `RenderLaunch` in `ExperimentDetailView`; one `connect` line in each of `LabMacApp` and `LabPhoneApp`; `LabDataService` job reads; `ReceiptRecord` titles and the no-undo sentence for job receipts; `LibraryMessages` for the new rule violations.
- `Tests/LabMacTests/RenderSurvivesHostTests.swift` (4, new) and `Tests/LabPhoneTests/RenderSurvivesPhoneTests.swift` (3, new).
- `project.yml` and the regenerated project (additions only, byte-identical over two runs): LabMac, LabPhone, and LabPhoneSurfaces link `LabJobs` and `RenderThatSurvives`; LabPhone and LabPhoneSurfaces declare `BGTaskSchedulerPermittedIdentifiers` = `$(PRODUCT_BUNDLE_IDENTIFIER).render.*`. No entitlement and no background mode was added. XcodeGen is not installed on research, so the project was regenerated on command with XcodeGen 2.46.0.
- `Config/ProductPolicy.txt`: CoreLocal macOS and iOS, and SystemSurfaces iOS, may link Core Image, Metal, Core Video, Core Media, and `_AVKit_SwiftUI`; iOS also BackgroundTasks.
- `Fixtures/LAB-032/` (new): six hostile recipes and their README.
- Docs: the experiment spec (`state: implemented`, implemented split, implementation notes), the regenerated catalog JSON, [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#jobs-and-progress), a row in [EXTENSION_AND_PERMISSION_MATRIX](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and a LAB-032 section in the [installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md#installed-sdk-ledger).

**Implementation steps:**

1. **Probe.** BackgroundTasks headers, the AVFoundation interface, and the Core Image, Metal, Foundation, and UIKit headers in the 27.0 SDKs. `BGContinuedProcessingTask` is iOS 26.0 only; `submit(_:)` is deprecated in iOS 27.0 for `submitTaskRequest(_:)`; background GPU needs an entitlement this lab does not request; Core Image and Metal are absent from the watchOS SDK. Details in the ledger and the spec's notes.
2. **File access and capacity.** `DestinationCheck` creates the experiment's folder if needed, refuses a file or a link, proves the folder writable with a probe file, and compares the volume's important-use capacity with the recipe's estimate. A refusal records no job.
3. **A durable foreground job.** `startJob` before any work; a checkpoint after each segment; launch recovery marks a job no worker runs as stopped (`app-stopped`).
4. **Continued processing only when qualified.** The iPhone runway asks only when the person allowed it, the app is active, and the wildcard is declared, with `strategy = .fail`. Otherwise the job is foreground-only and stops at its next frame when the app leaves (`left-foreground`), after asking for a short grace period. The Mac worker holds a user-initiated activity while it runs.
5. **Checkpoint, cancel, publish.** Segments are separate H.264 files renamed into place when finished; joining copies them without re-encoding; the joined movie's frame count and size are read back; one `rename(2)` publishes it. Stops are honored up to the rename and never after.
6. **Tests.** The domain operation (`JobTests`, `JobStoreTests`), cancellation at five points, expiration, a removed segment, a stop by another writer, Reset Demo during a run, invalid input (hostile recipes, field limits, job value validation), and the unavailable path (no store; too little space; no GPU).

**Evidence:** the LAB-032-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). The simulator runs used a throwaway UI-test target in a copy of this branch, not committed, on a simulator named "NL LAB-032-A harness" that was deleted afterwards; screenshots stayed in its result bundle on research and were removed with it.

**Not run:**

- Any physical device.
- Continued processing granted by iOS: the simulator answered "unavailable". A granted task, its system progress, and its real expiration ran only through a test runway.
- Background GPU: no entitlement is requested, so the app never uses it.
- Running out of space on a real volume; the mapping of the system's out-of-space errors is in the code, not exercised.
- An export cancelled mid-copy: the short fixture's join ends too quickly for the stop to land during it.
- A person quitting the Mac app by hand mid-render (the hosted test simulates an earlier process).
- VoiceOver, Voice Control, Full Keyboard Access, iPad layouts, a 26-SDK compile, and `build_manifest.py --lane Store`.

**Known limitations:**

- Receipts are listed for the app session only, as in CORE-005, and a long render adds one receipt per segment.
- Two hosts sharing one store (an app and an extension) would each recover jobs they do not run; today only the app runs renders, so a running job at launch can only be an orphan.
- If the success commit is lost after the rename, the new movie is published while the job still reads running; recovery marks it stopped, and Resume joins and publishes the same movie again.
- The schema moves to version 4. Another branch that also adds a version 4 must renumber at integration.
- Commit 2 (`LabJobs`) declares the render target whose sources arrive in commit 3, so it does not build on its own.

**Next dependency-ready ticket:** LAB-032-B (qualification). It needs this ticket and CORE-007, CORE-009, and CORE-010, all done. LAB-005-A, LAB-025-A, and LAB-033-A wait for LAB-032-B.
