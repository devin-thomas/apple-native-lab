---
id: "LAB-030-A"
title: "Implement Tactile Grammar"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-004-B"]
---

# LAB-030-A — Implement Tactile Grammar

## Goal

Design three distinguishable tactile cues and compare actual device output rather than treating haptics as decoration.

## Authority and scope

Read the [governing specification](../experiments/LAB-030-tactile-grammar.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** tactile-grammar module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Create success/warning/timing cues with original audio
3. Show visual and spoken equivalents
4. Route to supported device feedback
5. Provide a clear stop and intensity preference
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Unsupported actuators never crash a cue. (`CueOperationTests.anUnsupportedActuatorFallsBackWithoutFailingTheCue`, `missingActuatorsUseTheVisualPulseAndOptionalTone`. A throwing or missing actuator returns outcome `.fellBack` or fallback `.delivered` with the visual pulse and spoken words; the stand-in never crashes.)
- [x] Muted haptics leave every task usable. (`CueOperationTests.mutedHapticsLeaveTheCueUsable`. Intensity `.muted` takes the visual route, starts no haptic or tone, and still returns the spoken words and pulse.)
- [x] Repeated cues obey rate and fatigue limits. (`CueOperationTests.repeatedCuesObeyRateAndFatigueLimits`. A second success haptic inside the cue's gap is `.limited(.rate)`; a sixth haptic inside the fatigue window is `.limited(.fatigue)`; the visual and spoken path still complete.)
- [x] Fallback is usable: Visual pulse and optional quiet audio.. (`CueOperationTests.missingActuatorsUseTheVisualPulseAndOptionalTone`, `routerPrefersARealActuatorAndNeverAWatchWaveform`, `originalTonesAreQuietWavs`. With no actuator, the cue delivers the visual pulse and, when quiet audio is available, a synthesized WAV under 20 KB. The UI shows the pulse and spoken words.)
- [x] Sensitive operations share the domain authorization/receipt path. (`CueOperationTests.authorizationMatchesTheAdapterCeilingAndARetryReplays`, `aPolicyCanRefuseAnOtherwiseAllowedPlay`. Play checks adapter ceiling, grants, and `CueAuthorization`; a model tool may propose and cannot play; a retry of the same request ID returns the immutable receipt. `PlayTactileCueIntent` and the app UI both call `TactileGrammarCenter`.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No arbitrary custom waveform parity on Watch; controller support differs by device.

**Research:** [S49](../docs/SOURCE_INDEX.md#s49), [S50](../docs/SOURCE_INDEX.md#s50).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-030's spec now claims `implemented`. Package tests prove the domain operation, fallback, muted play, rate and fatigue limits, cancellation, invalid ids, and authorization. Hosts compile on Mac, iPhone, Watch, and Apple TV. Nothing here measured a physical actuator; LAB-030-B qualifies that.

**Changed:**

- `Packages/LabFeatures`: the `TactileGrammar` product and target (new), depending on LabDomain. Sources: `CuePattern`, `CueAudio`, `CueRouting`, `CueRecords`, `HapticActuator`, `LiveHaptics`, `TactileGrammarEngine`, `TactileGrammarModel`, `TactileGrammarIntent` (Play Tactile Cue). `TactileGrammarTests` (15 in `CueOperationTests`).
- Live adapters in the same target, compiled only where the SDK has them: Core Haptics and GameController on iOS, macOS, and tvOS; quiet `AVAudioPlayer` on iOS and macOS; `WKInterfaceDevice.play` on watchOS. Watch routes send one system haptic and an empty event list.
- `Apps/Shared/TactileGrammar/` (new): the page and catalog Open button. The visual pulse animates the cue's pulse count.
- `Apps/Mac/Window/TactileGrammarColumns.swift` (new). `Apps/Watch/TactileGrammarWatch.swift` (new).
- Shared host hooks, one case each:
  - `LabMacApp` / `LabPhoneApp` / `LabWatchApp`: install `LiveTactileGrammar.makeEngine()`.
  - `MainWindowState`: `.tactileGrammar` and a per-window model. `MainWindow`, `SidebarView`, `LabCommands` (View › Tactile Grammar, ⌥⌘5).
  - `ExperimentDetailView`: `TactileGrammarLaunch`.
  - `ActionAtlasHost`: `TactileGrammarIntentsPackage`.
  - `LabWatchApp`: catalog section and destination for LAB-030.
- `Packages/LabDomain`: public `AuthorizationDenial` initializer (tests and cue refusals construct the same denial value as OperationService).
- `project.yml` and regenerated project: LabMac, LabPhone, LabPhoneSurfaces, and LabWatch link `TactileGrammar`. Apple TV does not. Regeneration is byte-identical.
- `Config/ProductPolicy.txt`: CoreLocal and SystemSurfaces may link CoreHaptics, GameController, and AVFAudio (quiet cue tone). Companions watchOS may link WatchKit for system haptics and CryptoKit (TactileGrammar → LabDomain ContentDigest). No entitlement.
- Catalog: `experiments/LAB-030-tactile-grammar.md` (`state: implemented`, split, notes); regenerated `experiments.json`. Catalog tests expect 7 implemented, 41 specified.
- `Tests/LabMacTests/ActionAtlasHostTests.swift`: metadata expects `PlayTactileCueIntent`.
- `docs/SOURCE_INDEX.md` (S49, S50), `docs/VERIFICATION_BOUNDARIES.md`, and this record; rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** Installed SDK headers for Core Haptics, GameController, and WatchKit. Findings are in the spec notes and the verification ledger. On the research Mac, `supportsHaptics` was false; no cue was played.
2. **Three cues.** Success, warning, and timing: distinct spoken words, visual pulses, tones, and haptic event lists (or Watch system types).
3. **Visual and spoken.** Receipt and UI always carry both. Quiet tones are synthesized WAVs (no bundled media).
4. **Route.** Core Haptics, then controller, then Watch system, else visual fallback. Muted always falls back.
5. **Stop and intensity.** Stop bumps a generation and stops actuators. Intensity is muted / quiet / standard.
6. **Tests.** Domain play, cancellation, invalid pattern ids, unavailable actuators, rate/fatigue, authorization (ceiling, grants, policy), retry replay, Reset Demo scope.

**Not run:** any physical iPhone, Watch, or controller haptic; assistive-technology passes; a 26-SDK compile. Simulator and Mac package paths only.

**Next:** [LAB-030-B](LAB-030-B.md) qualifies on capable hardware.

