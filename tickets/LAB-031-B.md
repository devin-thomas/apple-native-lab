---
id: "LAB-031-B"
title: "Qualify and document Native Screening Room"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-031-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-031-B — Qualify and document Native Screening Room

## Goal

Prove Native Screening Room on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-031-native-screening-room.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** native-screening-room tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Audio interruptions and route changes preserve correct state; Caption selection survives a presentation change; Unavailable codec or protected content shows a real error
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Audio interruptions and route changes preserve correct state.
- [ ] Caption selection survives a presentation change.
- [ ] Unavailable codec or protected content shows a real error.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac, Apple TV.

**Unavailable path:** In-app local playback using a small universally supported fixture.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-031 stays `implemented`.** Mac package tests use real AVFoundation and AVPlayer over the original bundled clips; their interruption, route, and surface signals are injected. Mac hosted tests ran through the full gate. No physical-device qualification, manual assistive-technology pass, or state promotion is claimed.

**Acceptance.**

- [x] Audio interruptions and route changes preserve state: fixture only. `InterruptionAndRouteTests` (11) and the model tests passed recommendation/no-recommendation, person's pause, paused playback, duplicated interruption reports, lost/new output and output loss during interruption. The new clean replay checks the person's pause with a real player and file-backed state. No real audio-session event was produced.
- [x] Captions survive a presentation change: the domain/model tests passed; the new replay kept Spanish on the same player item between injected theater/page changes and through relaunch. The tvOS remote-driven simulator test passed the actual AVKit theater and Menu return with Spanish selected, at 0:00; see `screening-tvos-simulator.json`. Injected PiP/full-screen changes do not prove those surfaces ran.
- [x] Unavailable codec shows a real error: `ClipOpenerTests` and the model tests passed against AVFoundation itself: `lab0` is unsupported, the truncated clip gives -11829, and Test Card recovers. Protected content remains classification-only, never observed.
- [x] Evidence identifies toolchain, hashed clips, adapter and limitations: `evidence/LAB-031/`; Xcode 27.0 (27A266a), macOS 27.0 (26A425).
- [x] The walkthrough labels injected events and the simulated companion and makes no physical-device claim.
- [x] Publication-safe material: source review and bundled-byte hash tests. Original generated shapes/tone/written captions under MIT only. Two reviewed tvOS simulator screenshots show only the app and original Test Card, with ancillary metadata removed. No media export.

**Changed:** `ScreeningRoomQualificationTests` adds one complete clean replay with a temporary file store, a real player, resume, failing codec/recovery, reset and byte-identical preservation of an unrelated original sentinel. Five evidence records, two simulator screenshots, the walkthrough, the accessibility review, installed-SDK ledger, build-status rows and this record. The experiment spec links this qualification without changing state. No production source, shared host hook, entitlement, capability profile, target, project setting or generated catalog changed. No decision record is needed because behavior/platform/data ownership did not change.

**Platform results:** Mac hosted tests passed (184 passed, 0 failed, 1 expected failure, 3 skipped in the whole host run). Focused iPhone simulator test: 1 passed, no failures. Focused tvOS simulator run: 63 passed, no failures/skips, including the remote-driven native theater round trip. The separate Watch simulator smoke/package step passed (watchOS 27.0, 24R362). The release-policy manifest passed for CoreLocal, SystemSurfaces and Companions; optional profiles without schemes were skipped. Every simulator was created for this ticket and deleted by its run.

**Commands and results:** [BUILD_STATUS](../docs/BUILD_STATUS.md) contains the actual commands. Narrow run: 40 domain tests and 20 playback tests passed. The full gate ran once, with `LAB_SIMULATOR_PREFIX="NL LAB-031-B"`, and stopped with exit 65 at the unrelated speech test `SpeechTimelinePhoneTests.theOnDeviceRouteOrItsStatedFallbackRunsInsideTheApp()`. Its xcresult reports `Crash: NativeLab` (8 passed, 1 failed). Package checks and the Mac hosted step passed before it; no unrelated fix or skipped-test full-gate pass is claimed. Final `python3 script/validate/all.py` passed all 8 validators (35 evidence records), and local `git diff --check`, evidence-input hash checks and PNG metadata screening passed.

**Not run:** physical iPhone/iPad/TV; real calls, alarms, interruption notifications or unplugged output; native PiP/AirPlay, Control Center/Lock Screen/headphone/media-key commands; protected media; paired companion transport; cancellation of an in-flight asset load or the Reset confirmation; manual VoiceOver, Voice Control, Full Keyboard Access, large text or iPad layout; 26-SDK compile. Cancellation remains a qualification gap, not a passed test. Reset isolation uses an original sentinel, not real imported user data. The Mac has no AVAudioSession; its route handling belongs to the system.

**Owner follow-up:** The default tvOS screenshot shows the Spanish caption button breaking as "Span-ish"; selection still succeeds. Widening that caption row is a host accessibility follow-up. Test actual interruptions and routes on iOS, declared native playback surfaces and assistive technology on supported devices. Automatic caption preferences remain off on initial open, and Apple TV resume state in Caches remains purgeable. Investigate the unrelated speech crash before claiming a green integrated gate.

**Next dependency-ready ticket:** LAB-009-B (Documents Everywhere qualification; LAB-009-A, CORE-007, CORE-009 and CORE-010 are done).
