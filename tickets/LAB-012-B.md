---
id: "LAB-012-B"
title: "Qualify and document Point, Inspect, Propose"
status: "done"
milestone: "M3"
kind: "qualification"
depends_on: ["LAB-012-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-012-B — Qualify and document Point, Inspect, Propose

## Goal

Prove Point, Inspect, Propose on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-012-point-inspect-propose.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** point-inspect-propose tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Barcode payloads cannot execute actions; Photos containing private text remain local by default; Uncertain recognition stays an editable suggestion
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Barcode payloads cannot execute actions.
- [x] Photos containing private text remain local by default.
- [x] Uncertain recognition stays an editable suggestion.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Supported iPhone; iPad/Mac camera-import fallback.

**Unavailable path:** Image picker plus OCR and manual fields.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-012 stays `implemented`.** Qualification ran on the Mac and in the iPhone simulator, through hosted session methods on fresh SQLite stores. No physical iPhone/iPad, camera, live image-model description, system visual-search invocation, or manual assistive-technology pass ran. The [walkthrough](../docs/walkthroughs/LAB-012-point-inspect-propose.md) labels these boundaries. Five records live in [evidence/LAB-012](../evidence/LAB-012/), including the failed full gate.

**Acceptance.**

- [x] Barcode payloads cannot execute actions: `InspectionContractTests`, `PointInspectQualificationTests`, and `VisionAdapterTests`. Scripted action-looking codes become note text in a `createItem`; Vision's generated QR returns text. No real barcode action was invoked.
- [x] Private text remains local by default: scripted synthetic text with visual search off, the source route review, and `PrivacyRouteTests`. No real private photo or runtime network interception was used. Apply intentionally stores text in the local note; separately chosen downstream exports may carry it.
- [x] Uncertain recognition stays editable: the 0.42-confidence replay changes the title/body, adds nothing at review, then saves only on approval. Recognition is scripted in this case.
- [x] Toolchain, input hashes, adapters, and limitations: the five structured records name Xcode 27.0 (27A266a), macOS/iOS SDK 27.0, and the original and processed image hashes.
- [x] Walkthrough keeps replay and live integration distinct: static review. Hosted session calls are explicitly distinguished from a window, touch, picker, camera, model, or system intent run.
- [x] Public-safe material only: original geometric swatch and synthetic test text; no screenshots, recordings, or export archives were produced.

**Replay and failures.** Package tests passed 18 checks in 5 suites. The Mac's 3 focused hosted tests passed; the iPhone simulator's 1 focused replay passed. Both session replays show Fixture replay and Manual fields (not a model), write no receipt during Use These Fields, save one user item on Apply, and preserve it exactly through Reset Demo. Existing tests prove model-tool commit denial, empty/oversized/unsupported-header input refusal, empty-title refusal, cancellation, timeout, unavailable-model fallback, and one-approval retries. The new stale-approval test creates the reviewed item ID elsewhere; applying the old create cannot replace it. Distinct Apply actions are separate creates, not image-content deduplication.

**The iPhone hash correction.** The original PNG is 115 bytes with SHA-256 `5878b4eb086241d408b0ab74bcb3d48c42b035fa93d1766b5d3a43ee9f4a7105`. Mac bundling preserves it. The iOS build processes it into 138 bytes with SHA-256 `a4ef56265ebd8066a5c137987ac43445f2973879897e094389b03d33f2c23e2b`. The first simulator test incorrectly expected the source hash; the app correctly stored the consumed-byte hash. The test now compares against `SelectedImage` of the bundled bytes (491f004). Its focused rerun passed on iPhone 18 Pro, iOS 27.0 (24A434).

**Full gate.** `LAB_SIMULATOR_PREFIX="NL LAB-012-B" script/test.sh` ran once through `labr` at 3f0db77 and exited 65 at iPhone: the incorrect PointInspect hash assertion above and `RenderSurvivesPhoneTests.leavingTheForegroundWithoutBackgroundTimeStopsAtACheckpoint()` with `Crash: NativeLab`. Validators, validator self-tests, every package suite, and the complete Mac hosted step passed first. The unrelated render crash was not repaired. Watch, TV, and the manifest were not reached in that run; their original script steps were then run in a temporary continuation, without rerunning or relabeling the failed full gate. The continuation passed at 491f004 with documentation uncommitted: Watch Series 12 (46mm) / watchOS 27.0 (24R362), Apple TV 4K (3rd generation) / tvOS 27.0 (24J360), and Release Source-lane CoreLocal, SystemSurfaces, and Companions manifest checks. Its simulators were created and deleted for this ticket; the temporary script was removed. See the final command/results rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Changed:** PointInspect package qualification tests; Mac and iPhone hosted qualification tests; five evidence records; the walkthrough; experiment qualification notes and fixture-proved checkboxes; the shared accessibility and installed-SDK review documents; and BUILD_STATUS evidence rows. No production code, shared host hook, target, entitlement, purpose string, project setting, or catalog state changed.

**Not run:** physical iPhone/iPad, camera capture (not implemented), live image interpretation, system invocation of visual search, Mac/iPhone picker interactions, pointer/touch UI, manual VoiceOver/Voice Control/Full Keyboard Access, large-text or visual audits, OS-26 runtime, and a 26-family SDK compile. Camera/photo permission denial was not exercised: this implementation offers chosen files, not camera or photo-library authorization.

**Follow-ups:** dedicated Mac menu shortcuts; pinned iPhone Apply; explicit status announcements; moving synchronous file reading off the main actor; cancellation ownership when leaving the screen. These are source-review findings, not fixes or passing UI claims.

**Owner gate:** selected-image/manual interaction on a physical iPhone, then separately qualify any live-model and system visual-search claims and assistive-technology passes. No promotion to `device-verified` or `release-ready` is justified here.

**Next dependency-ready ticket:** LAB-013-B (LAB-013-A, CORE-007, CORE-009, and CORE-010 are done).
