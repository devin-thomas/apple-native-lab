---
id: "LAB-013-B"
title: "Qualify and document Speech Timeline"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-013-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-013-B — Qualify and document Speech Timeline

## Goal

Prove Speech Timeline on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-013-speech-timeline.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** speech-timeline tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Route changes do not silently lose the session; Final segments do not duplicate provisional text; Transcript corrections preserve the original media timestamps
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Route changes do not silently lose the session — scripted event/state-machine proof only; live capture remains blocked.
- [x] Final segments do not duplicate provisional text — generated streams and the live Mac file path.
- [x] Transcript corrections preserve the original media timestamps — all sources through both exports and a saved item.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations — Mac, fixture, and simulator records; not-run hardware gates stay explicit.
- [x] The walkthrough never claims a simulation is the live integration — each path is named, with no physical iPhone/iPad or recording claim.
- [x] Only approved original/public-safe material enters screenshots and exports — original script/captions and reviewed metadata records; no screenshots or synthesized audio added.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac subject to language/device support.

**Unavailable path:** Import a caption fixture or annotate manually; unsupported languages are stated.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.


## Completion record (2026-10-02)

**State: Speech Timeline stays `implemented`.** The Mac file-transcription route and iOS simulator fallback are qualified. No physical iPhone/iPad, live microphone, model download, or manual assistive-technology pass is claimed. Recording remains blocked on an owner decision about `NSMicrophoneUsageDescription` and the Mac audio-input entitlement. These gates do not prevent the caption/manual fallback.

**Continued work:** retained the existing qualification commits `a30d608` and `51cd668`; no merge or rebase from main. They add the domain and host qualification suites and fix overlapping late guesses, Unicode line separators, audio-stop mapping, duplicate Record presses, replaced-timeline save retries, and pause/resume announcements. This continuation reviewed and reran their tests.

**Launch crash:** the saved `pre-2` and `pre-5` result bundles blamed the active speech route and renderer-only tests, but their matching crash reports show `EXC_BREAKPOINT` / `SIGTRAP` in `LabFocusFilterIntent.appContext`. Focus expects a predicate against a filter-criteria string, not `request.identifier`. A control build with the old expression and the real context-construction regression reproduced `Crash: NativeLab` (exit 65, one speech-route pass and one crash). The correction uses `SELF IN` and sets the reminder's `filterCriteria` to its existing lab identifier ([ADR-LAB-013](../docs/adr/ADR-LAB-013.md)). The inherited synthesizer-lifetime rewrite and throwaway Focus probe were removed: the crash evidence did not support that theory.

**Changed shared hooks:** `Apps/Shared/SpeechTimeline/SpeechTimelineModel.swift` (earlier commit, session state and announcements); `Packages/LabFeatures/Sources/RespectfulAttention/AttentionIntents.swift` (one predicate correction needed for app launch); `Apps/Shared/RespectfulAttention/LiveAttentionSystem.swift` (one matching content field). The Focus package regression and real phone context construction cover the correction. The decision uses a ticket-scoped name because main already has a different ADR-016; main was only read, never merged. No targets, packages, settings, frameworks, entitlements, or purpose strings changed; no project regeneration or release manifest was needed.

**Evidence:** seven JSON records in [`evidence/LAB-013/`](../evidence/LAB-013/): two original LAB-013-A records retained, three freshly exported Mac hosted-test attachments, the expected-failure launch control, and the eight-run phone summary. The hosted attachments record `999b6a1-dirty`; phone repetition records `64b5c0e-dirty`, with the repeat script later committed unchanged as `999b6a1`. The script/caption hashes remain `c03523b…e52cdf0` and `1615650…e19ee4b`. Raw result bundles, simulator identifiers, crash diagnostics, stores, and generated audio are not committed. The [walkthrough](../docs/walkthroughs/LAB-013-speech-timeline.md) is text only; inherited screenshots without a retained generation command were omitted.

**Commands actually run:** every build/test command below ran through `labr` on the build host, never on the editing Mac. No full `script/test.sh` run.

| Command / check | Observed result |
|---|---|
| SDK headers/interfaces: `AVSpeechSynthesis.h`, `AVAudioEngine.h`, `UNNotificationContent.h`, and `AppIntents.swiftinterface`; `xcodebuild -version` | Xcode 27.0 (27A266a); iOS 27 SDK declarations recorded in the installed-SDK ledger. Linked Apple SpeechAnalyzer and Focus-filter primary sources consulted |
| `swift test --package-path Packages/LabFeatures --filter SpeechTimelineTests` | 62-test run passed, live opt-in probe skipped. The wrapper subsequently exited 1 because it used zsh's read-only variable `status`; the test process itself passed. Corrected wrapper used below |
| `swift test --package-path Packages/LabFeatures --filter "SpeechTimelineTests\|RespectfulAttentionTests"` | Both products passed: Speech Timeline 62-test run (live probe skipped), Focus adapter 13 tests |
| Old-predicate control: `xcodebuild … -scheme LabPhone-Core -only-testing:LabPhoneTests/SpeechTimelinePhoneTests test` | Expected failure, exit 65: context regression crashes, speech route passes; `build/focus-control.xcresult`. An earlier method filter selected zero tests and is excluded from passing evidence |
| `LAB_SIMULATOR_PREFIX="NL LAB-013-B" script/qualify_speech_timeline_phone.sh` | 8 of 8 targeted runs passed, 3 tests each, 24 passing executions; each summary requires 3 passes and 0 failures. `-only-testing:` selects only `SpeechTimelinePhoneTests` and `SpeechTimelinePhoneQualificationTests`; first run builds, subsequent runs use `test-without-building`. Ticket-created iPhone 18 Pro / iOS 27.0 (24A434) simulator deleted by the script |
| `TEST_RUNNER_LAB_LIVE_SPEECH=1 xcodebuild … -scheme LabMac-Core -destination platform=macOS -only-testing:` the four Speech Timeline host suites, `LAB_SOURCE_REVISION=999b6a1-dirty test` | 17 passed, zero failed/skipped. Includes the live synthesized-file route and 18 clean-state interaction observations. `xcresulttool export attachments` exported three structured records |
| Five host builds; `swift test --package-path Packages/LabDemo --filter SpeechTimelineEvidence`; `python3 script/validate/all.py`; `python3 script/generate_catalog.py`; `git diff --check` | LabMac-Core, LabPhone-Core, LabPhone-Surfaces, LabWatch and LabTV builds passed; all 7 records passed metadata-rights review (1 test); all 8 validators passed (35 records); catalog regenerated without change; whitespace check clean |

**Acceptance mapping:** route changes are proven by `RouteChangeQualification`, `aRouteChangePausesTheRecordingSaysSoAndResumeContinuesIt`, and the hosted fixture record (pause, keep final segments, remove/count unfinished text, announce, resume the same timeline). Final/provisional separation is proven after every update in 300 generated streams and on the live Mac file run (41 provisional updates, 4 final segments, no sampled overlap). Correction tests preserve ranges, word times and recognized text through captions, timeline export and save. Denial, cancellation, duplicate/stale requests, concurrent retry and both resets are covered by the package and host suites; saved user items stay unchanged. The rights review and explicit path labels bound publication claims.

**Known limits:** no explicit CPU-load generator or clean-install matrix was used for the eight simulator runs. The selected tests use Swift Testing scheduling; research was shared, but its load was not measured. Live notification delivery and a person adding a Focus filter are not qualified by the launch correction. Accessibility findings remain recorded in ACCESSIBILITY_REVIEW: Mac menu/keyboard access, announcements for caption/manual/reset results, iPhone Save placement, message color, and discoverability of Correct need manual review. Existing unrelated build warnings are recorded in BUILD_STATUS.

**Not-run gates:** real microphone routes/interruption/cancellation; physical iPhone/iPad availability and transcription; model installation; real voices/rooms or other languages; user-selected audio import via the system panels; VoiceOver, Voice Control, Full Keyboard Access, large-text/contrast checks; a 26-family SDK build; device transport or release checks.

**Next dependency-ready ticket:** LAB-014-A (Language Bridge); its CORE prerequisites are done and this scoped qualification supplies LAB-013-B. Live recording remains a separate owner gate rather than a prerequisite for the caption contract.
