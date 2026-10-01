---
id: "LAB-041-B"
title: "Qualify and document Trust Desk"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-041-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-041-B — Qualify and document Trust Desk

## Goal

Prove Trust Desk on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-041-trust-desk.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** trust-desk tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: A display-name change cannot change identity; Biometric failure retains a non-destructive recovery path; Passkeys are never misrepresented as exportable app secrets
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] A display-name change cannot change identity.
- [x] Biometric failure retains a non-destructive recovery path.
- [x] Passkeys are never misrepresented as exportable app secrets.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac; passkey service is optional.

**Unavailable path:** Local authorization and a clearly labeled passkey protocol simulation.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-041 stays `implemented`.** The clean replay passed in the sandboxed Mac host and the iPhone simulator. Local authorization outcomes are scripted, passkeys are a protocol simulation, and neither replay presses UI controls. The hosted replay uses the real scoped Keychain; the package replay uses memory. No physical-device run, biometric prompt, or system passkey ceremony ran.

**Acceptance.**

- [x] Display-name changes retain identity: package `aDisplayNameChangeDoesNotChangeIdentity`, `renamingDoesNotReplaceThePasskey`, and the complete qualification replay; both hosts' `theFixtureReplayKeepsOtherUserData` retain the identity and credential account after rename.
- [x] Biometric failure has non-destructive recovery: scripted package and Mac host failure followed by Confirm locally and an app-UI open receipt. The added cancellation/unavailability test retains an existing open record and secret; expiry/revocation refuse opening. No actual sensor failure was observed.
- [x] Passkeys are not exportable app secrets: package copy/export refusal, stable user handle after rename, and passkey assertion without a local grant refusing the open. Hosted summaries retain the simulation label.
- [x] Evidence names toolchain, input hashes, adapters and limits: four records in `evidence/LAB-041/`, all at `4a73858-dirty`, distinguishing package fixture, Mac hosted fixture, iPhone simulator and static review.
- [x] Walkthrough labels every simulation and leaves live authentication unverified.
- [x] Retained material is original/public-safe fixture metadata and source hashes. No screenshot, recording or secret export was produced.

**Failure and reset cases:** `deniedCommitWritesNeitherRecordNorSecret` uses a read-only actor; `aStaleOpenDoesNotWriteASecret` advances the store revision before the open and confirms a conflict receipt with no secret write. Existing tests cover cancelled commits, invalid names, unavailable lab/secret store, duplicate opens, expiry, revocation, and Reset Demo/Desk beside unrelated user and demo data. The clean replay resets and opens again. Both hosts keep an original synthetic imported user item through Reset Desk. The existing secret-write compensation is best effort across two stores; its rollback can fail under concurrent edits. No behavior change was made here.

**Changed:** one package qualification file (4 tests), one hosted qualification file in each Mac/phone target (1 test each), four evidence records, the walkthrough, static accessibility review, installed-SDK notes, this ticket and BUILD_STATUS. No host hooks, capability descriptor changes, project settings, entitlements, targets or catalog regeneration. Source remains as LAB-041-A delivered it.

**Commands/results:** all builds/tests through `labr` on research. `swift test --package-path Packages/LabFeatures --filter TrustDesk`: 19 passed initially; 20 passed with the read-only denial case added. Focused `LabMac-Core` tests for `TrustDeskHostTests` and `TrustDeskQualificationHostTests`: passed. SDK probe: Xcode 27.0 (27A266a), macOS 27.0 (26A425), SDK 27.0; headers confirm `interactionNotAllowed`, `credentialID`, and `rawClientDataJSON`. `rg` was absent on research; the probe was repeated with `grep`.

The first `script/test.sh` attempt stopped at a walkthrough link because its mirror was synced before the evidence folder was written. Restart with all files synced: validators and self-tests, all package checks, and Mac hosted tests passed. Phone action: 9 passed, 1 failed, `SpeechTimelinePhoneTests/theOnDeviceRouteOrItsStatedFallbackRunsInsideTheApp(): Crash: NativeLab`. `xcresulttool get test-results tests` confirms the Trust Desk phone test passed (0.052 seconds); Mac Trust Desk suites also passed. Full gate therefore **failed**, not passed. This unrelated speech crash was not changed. The separately run Watch and TV tests passed in freshly created simulators (watchOS 27.0 / 24R362, tvOS 27.0 / 24J360), as did the Release Source-lane manifest for CoreLocal, SystemSurfaces and Companions. CloudOptional and FrontierOptional had no attached targets and were skipped. See BUILD_STATUS. A first remaining-check invocation sourced a Bash helper under Zsh and failed on `//AppleNativeLab.xcodeproj`; its created simulator was cleaned by its exit trap, and the corrected invocation uses explicit paths.

`python3 script/validate/all.py` through `labr` passed 8/8 after the completion records and all four evidence files were written. `git diff --check` passed.

**Not run:** physical iPhone/iPad, live biometry/device passcode, system passkey registration/assertion with a real relying party, manual VoiceOver/Voice Control/Full Keyboard Access, large-text/contrast/focus audit, 26-SDK compile, screenshots/recordings. Watch and TV do not link Trust Desk. No account, network ceremony, credential export, purchase, or publication.

**Owner/lead follow-up:** reproduce the unrelated Speech Timeline simulator crash before claiming a green repository gate. Perform owner-led live authentication and manual accessibility checks; production passkeys need relying-party/domain configuration. Static findings: grant display has no timed refresh, credentials are limited to two lines, individual desk actions lack Mac menu commands. None establishes release readiness.

**Next dependency-ready ticket:** [LAB-042-B](LAB-042-B.md), whose implementation and foundation dependencies are done.

**Remaining checks, exact remote command (through `labr`):**

```sh
set -e
for platform in watchOS tvOS; do
  sim=$(python3 script/simulator.py create "$platform" "NL LAB-041-B remaining $platform")
  trap "python3 script/simulator.py delete $sim" EXIT
  if [[ "$platform" == watchOS ]]; then scheme=LabWatch; else scheme=LabTV; fi
  xcodebuild -project AppleNativeLab.xcodeproj -scheme "$scheme" -destination "id=$sim" -derivedDataPath build/DerivedData -collect-test-diagnostics never LAB_SOURCE_REVISION=4a73858-dirty test -quiet
  python3 script/simulator.py delete "$sim"
  trap - EXIT
done
python3 script/build_manifest.py
```
