---
id: "LAB-032"
title: "Render That Survives"
state: "implemented"
milestone: "M2"
category: "Media"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-032 — Render That Survives

## The moment

Start a render, leave the screen, return, and see a truthful recoverable job instead of a vanished spinner.

## Scope and native leverage

**Hosts:** iPhone/iPad user-started background work; Mac foreground worker.

**Primary APIs:** AVFoundation export, BackgroundTasks, optional GPU path. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** RenderRequest, JobCheckpoint, ExportArtifact. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Validate file access and destination capacity
2. Create a durable foreground job
3. Use continued processing only when qualified
4. Checkpoint, cancel, and atomically publish output

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Cancellation never replaces a good output with a partial file.
- [ ] Task expiration produces a resumable or clearly failed job.
- [ ] GPU-unavailable uses a supported lower-cost path.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Background APIs do not promise completion, launch at arbitrary times, or infinite agent execution.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Keep the job foreground; Mac worker only while explicitly running.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/render-that-survives/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-032-A):

- `Packages/LabDomain`: the job itself, for every lab that runs finite, expensive work. `LabJob` has a kind, a title, a phase (running, interrupted with a reason, succeeded with its output, failed, or cancelled), durable progress with an optional total, a revision, and a namespace. `DomainOperation.startJob(draft:)` and `updateJob(id:expected:transition:)` change it; neither is destructive or undoable, and a finished job never changes. Reset Demo removes demo jobs. The contract is in [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#jobs-and-progress). The proposed types map as `RenderRequest` → `RenderRecipe` plus `startJob`, `JobCheckpoint` → `JobProgress` at a revision, and `ExportArtifact` → `JobOutput`.
- `Packages/LabStore`: schema version 5 adds the `jobs` table (version 4 is LAB-043's lab alerts).
- `Packages/LabFeatures/Sources/LabJobs/` (new, reusable): `JobBackend` and `ServiceJobBackend`, `JobRecorder` (one step per request, at the last revision seen, retrying a lost commit under its request ID), `JobRecovery` (running jobs no worker owns become interrupted at launch), `JobStopSignal`, `DestinationCheck` (folder, write probe, and capacity), `AtomicPublication` (one `rename(2)`), and the `JobRunway` protocol with the foreground runway and the Mac worker's. Foundation only.
- `Packages/LabFeatures/Sources/RenderThatSurvives/` (new): the fixture recipes, `FramePattern` with the CPU and GPU painters and their check, the segment encoder and the assembler (AVFoundation), `RenderWorker` (one run from the last checkpoint to a published movie), and `RenderStudio` (start, resume, stop, recovery, and Reset Demo's cleanup). It never opens the store.
- `Apps/Shared/RenderSurvives/`: `LibraryJobBackend` (reads as the app UI through `LabDataService`, commits through `LabLibrary.submit`), `RenderStudioModel`, and the views. `Apps/Phone/Jobs/ContinuedProcessingRunway.swift`: the iOS runway. The Mac reaches the experiment from the sidebar and View › Render That Survives (⌥⌘0), with its columns in `Apps/Mac/Window/RenderColumns.swift`; iPhone and iPad from this experiment's catalog page.
- `Fixtures/LAB-032/`: hostile recipes. The two valid recipes are a resource of the module.

## Implementation notes (LAB-032-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs, on the Mac and in an iOS 27.0 simulator. These are compile, test-process, and simulator facts, not device proof.

- **Installed SDK.** `BGContinuedProcessingTask`, `BGContinuedProcessingTaskRequest(identifier:title:subtitle:)`, its `strategy` (`.fail` or `.queue`, default `.queue`) and `requiredResources` (`.gpu` needs the `com.apple.developer.background-tasks.continued-processing.gpu` entitlement), and `BGTaskScheduler.supportedResources` are iOS 26.0 and unavailable on macOS, tvOS, watchOS, and visionOS. A continued-processing handler may be registered after launch, but an identifier may be registered only once, so each request uses a new identifier under the Info.plist wildcard. `BGTaskScheduler.submit(_:)` is deprecated in iOS 27.0 for `submitTaskRequest(_:) async throws`, which the iPhone host uses under `LAB_SDK_27` and on iOS 27. `BGTaskScheduler.Error.immediateRunIneligible` is what `.fail` returns when the system cannot run the task now. `AVAssetExportSession.export(to:as:isolation:)` and `states(updateInterval:)` exist and are unavailable on watchOS; `AVAssetWriter` is unavailable on watchOS; `CIContext(mtlDevice:options:)` and `MTLCreateSystemDefaultDevice()` exist on iOS and macOS. The Watch SDK has no Core Image or Metal framework, so the render module compiles out on watchOS.
- **The job is domain state.** A render's truth lives in the store beside its receipts, so a relaunch shows what was committed: running (with a worker in this process), stopped and resumable (with its reason), or finished. At launch a render job still marked running with no worker in this process is recorded as stopped because the app stopped while it ran. The app never shows a spinner for a job no worker runs.
- **Segments are the checkpoints.** A render is split into segments; each is its own H.264 movie that starts with a key frame, written to a `.partial` name and renamed when the writer finishes, and each is followed by a checkpoint commit. A resumed job starts after its last checkpoint, and re-encodes a finished segment whose file is gone without moving progress back. Joining uses a composition and the passthrough preset, so segments are copied, not encoded again. The joined movie is read back (frame count by counting samples, size, duration) before it may be published.
- **Publishing is one rename.** The checked movie is renamed over the previous output on the same volume. A stop request is honored at every frame, between segments, during joining, and just before the rename, and never after it. A cancel removes the job's work folder; the previous output keeps its bytes.
- **Two drawing paths, one image.** The GPU path composites the frame's rectangles with Core Image on the Metal device, with color management off, into the encoder's pixel buffer. The CPU path writes the same rectangles into memory. They produce identical bytes (tested on the Mac for the short and long recipes), every GPU frame is checked at sample points, and a frame that fails is drawn again on the CPU. The CPU path is used when there is no Metal device, when the person turns the GPU off, and on iPhone and iPad whenever the app is in the background, where it may not use the GPU without an entitlement this lab does not request.
- **Where a job may run.** The Mac worker runs while Native Lab is open and holds a user-initiated activity so App Nap does not slow it; quitting stops it, and the next launch shows it stopped. On iPhone and iPad a render asks for continued processing only when the person allowed it, the app is in the foreground, and the app declares the identifier wildcard; the request uses `.fail`, so it runs now or not at all. Without it the job is a foreground job: when the app leaves the foreground, it asks for a short grace period, stops at the next frame, and records the stop as `left-foreground`, resumable. In the iOS 27.0 simulator, iOS answered the request as unavailable, so the simulator ran the foreground job; a granted request has not been observed.
- **Space and access.** Before a job exists, the experiment's folder is created if needed, proved writable with a probe file, and its volume's space for important use is compared with the recipe's estimate (every segment plus the joined copy). A refusal records nothing. Running out of space during a run stops the job as `out-of-space`, resumable; that path is tested only through the error mapping, not by filling a disk.
- **Fixtures.** The frames are generated from numbers alone; no media is read. The long recipe is paced at playback speed, so it takes about 24 seconds and there is time to leave and return; the pacing is part of the recipe and is labeled in the app. Outputs stay in the app's container: tens of KB for the short recipe, under 2 MB for the long one.

## Delivery

[Implementation ticket](../tickets/LAB-032-A.md) → [qualification ticket](../tickets/LAB-032-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S28](../docs/SOURCE_INDEX.md#s28), [S41](../docs/SOURCE_INDEX.md#s41). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
