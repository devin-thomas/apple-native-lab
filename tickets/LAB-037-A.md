---
id: "LAB-037-A"
title: "Implement Home Scene Sandbox"
status: "done"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-037-A — Implement Home Scene Sandbox

## Goal

Preview a home-scene diff, execute only selected harmless actions, and explain partial failure.

## Authority and scope

Read the [governing specification](../experiments/LAB-037-home-scene-sandbox.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** home-scene-sandbox module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use simulated lights first
3. Request access to the selected home
4. Preview on/off/brightness changes
5. Commit and report per-accessory outcomes
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] A disconnected lamp does not mark the whole scene successful. (`HomeSceneOperationTests.aDisconnectedLampDoesNotMarkTheWholeSceneSuccessful`: living lamp succeeds, hallway lamp fails with “disconnected”, `sceneSucceeded` is false, and the OperationService receipt note says the scene did not succeed.)
- [x] Locks, doors, alarms, and heating are excluded by default. (`fictionalHomeExcludesLocksDoorsAlarmsAndHeatingByDefault`: four excluded accessories; selecting each throws `sensitiveKindExcluded`; preview lists them as excluded.)
- [x] A revoked home permission stops live mode. (`revokedHomePermissionStopsLiveMode`: authorized live route, then `revokeTo(.denied)` makes `refreshHome` throw `permissionRevoked` and forces `.simulated`; a later live request stays simulated.)
- [x] Fallback is usable: Deterministic fictional home with no real accessories. (`fictionalFallbackRecordsThroughOperationService` and the Mac/iPhone hosts: `FictionalHomeSource` only; labeled simulation; no HomeKit link in CoreLocal.)
- [x] Sensitive operations share the domain authorization/receipt path. (Every commit is `createItem`/`updateItem` through `HomeSceneBackend` → `LabLibrary.submit` → `OperationService` as app UI; model tools cannot commit. Package tests assert `receipt.admitted.adapter == .appUI`.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** HomeKit does not expose every vendor API; Matter controller work is separate from a HomeKit client.

**Research:** [S44](../docs/SOURCE_INDEX.md#s44).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-037's spec claims `implemented`. The fictional home preview/commit path ran in package tests. Mac and iPhone hosts link the module. Nothing is device-verified. No live HomeKit home was accessed. HomeKit is not linked in CoreLocal.

**Changed:**

- `Packages/LabFeatures`: the `HomeSceneSandbox` product and target (new), depending on LabDomain only, and `HomeSceneSandboxTests` (new): `HomeSceneOperationTests` (17).
- `Packages/LabFeatures/Sources/HomeSceneSandbox/` (new): `AccessorySnapshot`, `SceneProposal`, `FictionalHome`, `HomeAccess`, `HomeSceneSandbox`, `HomeSceneBackend`, `HomeSceneError`, `HomeKitPlatformFacts`.
- `Apps/Shared/HomeSceneSandbox/` (new): `HomeSceneSession`, `LibraryHomeSceneBackend`, `HomeSceneForm`, `HomeSceneScreen`, `HomeSceneLaunch`.
- `Apps/Mac/Window/HomeSceneColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState`: destination and per-window session.
  - `MainWindow`: columns and search prompt.
  - `SidebarView`: row.
  - `LabCommands`: View › Home Scene Sandbox (⌘9).
  - `ExperimentDetailView`: Open Home Scene Sandbox.
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `HomeSceneSandbox`. No HomeKit entitlement or purpose string. Watch and TV do not link it.
- `Fixtures/home/` (new): `fictional-home.json` and README with preview/commit/reset instructions.
- `experiments/LAB-037-home-scene-sandbox.md`: `state: implemented`, the module split, and implementation notes. Catalog JSON regenerated. Catalog tests expect seven implemented experiments.
- `docs/SOURCE_INDEX.md` (S44), `docs/VERIFICATION_BOUNDARIES.md` (HomeKit ledger), `docs/BUILD_STATUS.md`.
- `Tests/LabMacTests/HomeSceneHostTests.swift` (new).
- This record.

**Implementation steps:**

1. **Probe.** iOS 27.0 HomeKit headers and a Swift typecheck against the installed SDK: `HMHomeManager.authorizationStatus`, `HMAccessory.isReachable`, light/lock/door/alarm/thermostat service types, power/brightness characteristics. macOS SDK has no HomeKit. Recorded in the installed SDK ledger.
2. **Simulated lights first.** `FictionalHomeSource` with living + hallway lamps; hallway starts disconnected.
3. **Request access.** `requestLiveAccess` / `HomePermission`; CoreLocal live path unavailable without HomeKit; scripted source proves revoke.
4. **Preview.** On/off/brightness diffs; exclusions listed.
5. **Commit.** Per-accessory outcomes; scene success only when every selected light succeeds; receipt via OperationService.
6. **Tests.** Domain operation, cancellation, denied commits, stale preview, duplicate replay, incomplete outcomes, invalid input, unavailable live route, revoke, reset.

**Not run:** Physical iPhone/iPad with HomeKit entitlement; a real home; VoiceOver / Voice Control / Full Keyboard Access; iPad layouts; 26-SDK compile; Matter controller.

**Next:** [LAB-037-B](LAB-037-B.md) (qualification).

**Resumed review and corrections:** Fictional outcomes are evaluated without changing state. OperationService must accept the run before fictional light state is published. A cancelled or denied backend leaves lamps unchanged. Reset restores both lamp values and the owned run note. Duplicate requests in a session replay their original operation through OperationService (authorization is checked again), and overlapping commit/reset calls are refused. A changed home requires a fresh preview; route changes invalidate the cached home and selection. Success requires exactly one successful outcome for every selected accessory. Fictional access requests remain simulated. Live writes are explicitly unavailable; the permission stand-in is test evidence only.

**Decision:** [ADR-LAB-037](../docs/adr/ADR-LAB-037.md) records the fictional-only implementation and run-note ownership. Session lamp state is ephemeral. The owned collection/item use the user namespace because only the global demo seed creates demo entities; experiment reset updates only its stable item and retains receipts.

**Verification interruption:** The first resumed `LAB_SIMULATOR_PREFIX="NL LAB-037-A" script/test.sh` run passed repository validation, all 93 validator self-tests, and all package suites (including 14 Home Scene tests). It exited 129 before the Mac hosted step, without a failing-test diagnostic. Share Ingress reported its two existing known issues (cross-surface duplicate identifier conflict and same-second ordering). Research subsequently entered a simulator-move quiet window. No host or Release result is claimed for that attempt.

**Final narrow run:** `swift test --package-path Packages/LabFeatures --filter HomeSceneSandboxTests`, through `labr` on research, passed 17 tests in 1 suite on the package source committed as `3d91ead`. Added checks prove replays are authorized again, conflicting selections cannot reuse a completed request ID, and conflict receipts from a stale stored revision do not publish lamps or reset them. The host refreshes after a conflict and uses a new request ID on retry. Evidence: [domain-fixture.json](../evidence/LAB-037/domain-fixture.json).

**Full gate (resumed retry):** `LAB_SIMULATOR_PREFIX="NL LAB-037-A" script/test.sh`, through `labr` on research, exited 0 with “All automated checks passed” at `3d91ead-dirty`. Validators and their 93 self-tests, all package suites (17 Home Scene tests), Mac hosted tests, iPhone/Watch/TV simulator tests, and Release profile policy checks completed. `xcresulttool get test-results summary` confirmed all four bundles as Passed: Mac 133 total / 130 passed / 0 failed / 2 skipped; iPhone 4 passed; Watch 115 passed; TV 116 passed. `xcresulttool get test-results tests` confirmed the HomeSceneHostTests case as Passed. Simulator versions: iPhone 18 Pro, iOS 27.0 (24A434); Apple Watch Series 12 (46mm), watchOS 27.0 (24R362); Apple TV 4K (3rd generation), tvOS 27.0 (24J360). These are simulators, not physical hardware.

**Release manifest:** CoreLocal (Mac + Phone), SystemSurfaces, and Companions built with the 27.0 SDKs in the Source lane. CloudOptional and FrontierOptional skipped because no scheme builds their targets. No HomeKit capability was added. The existing two Share Ingress known issues remain. The Mac compiler emitted an exit-0/no-output diagnostic and typed-catch warnings in HomeSceneSession; the result bundle and overall gate passed. No claim is made for skipped checks.

**Final repository check:** `python3 script/validate/all.py`, through `labr` on research, passed all 8 checks (including 30 valid evidence records, current catalog, and dependency graph). Catalog generation already ran through `labr`; its generated bytes were unchanged from the local generated catalog. The project target links were retained from the preceding agent's generated project; no additional project settings changed during resumed work.
