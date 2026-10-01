---
id: "LAB-030-B"
title: "Qualify and document Tactile Grammar"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-030-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-030-B — Qualify and document Tactile Grammar

## Goal

Prove Tactile Grammar on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-030-tactile-grammar.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** tactile-grammar tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Unsupported actuators never crash a cue; Muted haptics leave every task usable; Repeated cues obey rate and fatigue limits
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Unsupported actuators never crash a cue.
- [x] Muted haptics leave every task usable.
- [x] Repeated cues obey rate and fatigue limits.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Capable iPhone, supported controllers, Watch system haptics separately.

**Unavailable path:** Visual pulse and optional quiet audio.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-030 stays `implemented`.** Qualification is limited to fixture/domain results, a muted live Mac engine, and a muted iPhone simulator engine. No physical iPhone, Watch, or controller output was run; nothing here promotes an actuator to device-verified.

**Acceptance.**

- Unsupported actuators: `anUnsupportedActuatorFallsBackWithoutFailingTheCue` and `missingActuatorsUseTheVisualPulseAndOptionalTone` pass with stand-ins. All three cues complete from clean engines without an actuator.
- Muted task: `aCleanReplayKeepsAllThreeMutedAndUnavailableCuesUsable` retains each visual/spoken value; `theInstalledMacAdapterCompletesEveryMutedCue` uses the live Mac engine without starting output. The simulator host test checks the same contract inside the iPhone app.
- Repetition: `repeatedCuesObeyRateAndFatigueLimits`, three `eachCueAdmitsAtItsExactRateBoundary` cases, and `fatigueExpiresAtTheWindowBoundaryAndMutedCuesDoNotConsumeIt` pass. These prove sequential injected-clock admission, not hardware timing or concurrent admission.
- Evidence: records in `evidence/LAB-030/` identify the measured toolchain, source revision, input source hashes, path, steps, results, and limitations.
- Walkthrough: [Tactile Grammar](../docs/walkthroughs/LAB-030-tactile-grammar.md) explicitly distinguishes fixture, simulator, and unrun physical output. “Spoken” is accessible text, not a narration claim.
- Rights/privacy: only original cue definitions and qualification test source enter evidence. No screenshots, recordings, exports, user data, accounts, or real media were collected. No network/cloud adapter, capture permission, entitlement, or target was added.

**Failure cases:** existing package tests prove invalid input commits nothing; adapter ceiling, grants, and narrower policy deny play; identical completed requests replay one receipt; changed payloads reuse no ID; Stop invalidates an in-flight cue; reset clears only this engine's log. A cue has no entity revision or imported-data store; stale state is a generation change. Reset-dialog cancellation and imported-data UI journeys were not driven.

**Changed:** package qualification tests and `Tests/LabPhoneTests/TactileGrammarPhoneTests.swift`; evidence, walkthrough, experiment qualification notes, installed-SDK qualification note, accessibility findings/matrix, this record, and BUILD_STATUS rows. No app hooks, project.yml edits, project regeneration, catalog state change, or behavior changes.

**Commands/results:** the narrow `CueOperationTests` run passed 19 tests (including three parameterized rate cases). `script/toolchain_report.sh` and the `CHHapticEngine.h` probe ran through `labr`; Xcode 27.0 (27A266a), Swift 6.4, SDK family 27.0, Apple M5 Max, macOS 27.0 (26A425). The full four-platform `script/test.sh` passed at `e75c668-dirty`, including the named iPhone simulator test (confirmed by xcresulttool), and the release manifest passed CoreLocal, SystemSurfaces, and Companions. All eight final repository validators passed. Results are recorded in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run:** physical iPhone/controller/Watch output; audio through a speaker; person-driven UI; VoiceOver, Voice Control, Full Keyboard Access, largest text or display-setting passes; iPad; a 26-SDK compile; concurrent in-flight duplicate/rate admission. Watch and TV smoke builds do not qualify haptic output. Apple TV does not link this feature.

**Follow-ups:** source review found no Reduce Motion check or automatic result announcement, no individual Mac cue menu commands, no Watch reset/pulse row, identical pulse values not restarting the task, Watch Stop unable to interrupt system haptics, Reset Demo not invoking actuator stop, and the controller adapter converting continuous events to transients. Details are in the walkthrough. Owner device and manual accessibility runs remain required before release.

**Next dependency-ready ticket:** LAB-019-B (its implementation and shared prerequisites are done). LAB-044-A still needs LAB-019-B; LAB-046-A still needs LAB-023-B.
