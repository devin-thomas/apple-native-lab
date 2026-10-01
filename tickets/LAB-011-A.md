---
id: "LAB-011-A"
title: "Implement Model Routing Observatory"
status: "done"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-010-B"]
---

# LAB-011-A — Implement Model Routing Observatory

## Goal

See where a request would run, what may leave the device, and why a larger model is or is not available.

## Authority and scope

Read the [governing specification](../experiments/LAB-011-model-routing-observatory.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** model-routing-observatory module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Keep local-only as the default policy
3. Model PCC eligibility separately from model availability
4. Show exact outgoing fields before a cloud request
5. Record route and usage without raw prompt telemetry
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Cloud-off causes zero cloud requests. (`CloudOffTests.cloudOffCausesZeroCloudRequests`: `RoutingPolicy.localOnly` never increments `cloudSendAttempts` or the counting transport.)
- [x] Missing entitlement is an explained gate. (`EntitlementGateTests`: closed `com.apple.developer.private-cloud-compute` appears in the decision reason; CoreLocal default closes entitlement, program, and distribution.)
- [x] Exhausted quota never silently switches to a paid provider. (`QuotaExhaustionTests`: quota-closed decision stays on local fallback; `PaidProvider.supportedProviders` is empty; transport stays at zero.)
- [x] Fallback is usable: Local generation or manual workflow; no mandatory third-party key. (`FallbackTests`; local summary and manual answer complete without cloud.)
- [x] Sensitive operations share the domain authorization/receipt path. (`AuthorizationReceiptTests`: local annotation proposes as the model-tool adapter and commits as the app UI through `OperationService`; the proposer cannot commit.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** PCC requires qualifying program enrollment, account entitlement, eligible distribution and user availability; not a free API for every source build.

**Research:** [S06](../docs/SOURCE_INDEX.md#s06), [S07](../docs/SOURCE_INDEX.md#s07).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-011's spec now claims `implemented`. Package acceptance tests and the host workflow are verified only by the actual runs listed below. Nothing here is device-verified, and no live Private Cloud Compute send ran.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `ModelRouting` product and target, and `ModelRoutingTests`.
- `Packages/LabFeatures/Sources/ModelRouting/` (new): `InferenceRoute`, `RoutingPolicy`, `ConsentGrant`, `OutgoingFieldPreview`, `PCCEligibility`, `UsageReceipt`, `RouteResolver` / `ModelRoutingFlow`, `CloudTransport` (`RefusingCloudTransport`, `CountingCloudTransport`), `RoutingProbe`, `ModelRoutingBackend` / `LocalFallbackCommit`, and the bundled fixture resource.
- `Packages/LabFeatures/Tests/ModelRoutingTests/` (new): 23 tests in 9 suites.
- `Apps/Shared/ModelRouting/` (new): session, host backend, shared page content, catalog launch.
- `Apps/Mac/Window/ModelRoutingColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState`: `modelRouting` destination and pane selection.
  - `MainWindow`: columns.
  - `SidebarView`: one row.
  - `LabCommands`: View › Model Routing Observatory (⌘9).
  - `ExperimentDetailView`: `ModelRoutingLaunch`.
- `project.yml` and the regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `ModelRouting` and bundle the routing fixture. No new entitlement. XcodeGen and its setting presets were copied to the mirror’s ignored build folder, then regeneration ran on research and the project was copied back.
- `Fixtures/routing/` (new): original sample prompt and README.
- `experiments/LAB-011-model-routing-observatory.md`: `state: implemented`, the implemented split, and implementation notes. Catalog JSON regenerated.
- `Tests/LabMacTests/ModelRoutingHostTests.swift`: fixture workflow over a fresh SQLite store, review before commit, duplicate approval, manual fallback, and reset.
- [ADR-015](../docs/adr/ADR-015.md): refusing transport, proposed envelope, explicit annotation review, and reset semantics.
- `LabCatalogTests`: 7 implemented experiments (41 specified).
- `docs/SOURCE_INDEX.md` (S07), `docs/VERIFICATION_BOUNDARIES.md`, `docs/DATA_CONTRACTS.md` (model routing), and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** Read `PrivateCloudComputeLanguageModel` from the macOS 27.0 SDK interface: availability, quotaUsage, errors. Entitlement string `com.apple.developer.private-cloud-compute`. Findings in S07 and the spec notes.
2. **Local-only default.** `RoutingPolicy.localOnly`; cloud-off tests prove zero transport sends.
3. **PCC vs on-device.** Separate `OnDeviceAvailability` and `PCCEligibility` gates.
4. **Outgoing fields.** The lab’s proposed request envelope (not a captured Apple wire payload) lists `prompt`, `locale`, `model`, `sampling` before any send.
5. **Usage without prompts.** `UsageReceipt` keeps names and lengths; diagnostics use character counts only.
6. **Tests.** Domain operation, cancellation, invalid input, unavailable PCC path, authorization/receipt path.

**Not run:**

- A physical device.
- A live PCC send (CoreLocal has no entitlement; transport refuses).
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- A 26-family SDK compile.
- watchOS PCC path (optional; Watch host does not link ModelRouting).

**Known limitations:**

- CoreLocal cannot open the entitlement, program, or distribution gates; PCC stays explained-closed.
- The optional paid-provider adapter is intentionally absent.
- The host workflow test calls the session inside the app; it does not drive the visible controls.

**Next dependency-ready ticket:** LAB-011-B (qualification). Also ready from LAB-010-B: LAB-015-A, LAB-006-A.

**Review repairs:** unknown PCC gates now fail closed; PCC SDK symbols have a compiler guard because package targets do not inherit `LAB_SDK_27`; local usage summaries no longer copy prompt-derived text; consent is consumed before transport admission and invalidated on eligibility changes; transport errors record delivery as unconfirmed without error text, and an unaccepted transport result does not claim that delivery never occurred; canonical preview digests use length prefixes; summary generation no longer commits automatically, and annotation retries keep their request ID. Cancellation testing uses a deterministic cancelling transport and awaits the result instead of accepting either outcome.

**Commands and results (all builds and tests through `labr` on research):**

- `script/toolchain_report.sh`: macOS 27.0 (26A425), Apple M5 Max, Xcode 27.0 (27A266a), Swift 6.4, 27.0 SDK family. The first combined probe failed with `zsh:1: command not found: rg`; the replacement `grep` probe succeeded.
- `grep -n -A 100 "class PrivateCloudComputeLanguageModel" …/FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface`: installed declarations read successfully; S07 records signatures and constraints.
- `PATH="$PWD/build/bin:$PATH" script/generate_project.sh`: passed using XcodeGen 2.46.0 and its setting presets in the mirror’s ignored build directory. The first setup attempt exited 69 because XcodeGen was absent; a binary-only attempt lacked setting presets, so its output was discarded and regenerated with the presets. The final project was copied back with `rsync`; no hand editing.
- `swift test --package-path Packages/LabFeatures --filter ModelRoutingTests`: final run passed, 23 tests in 9 suites. Earlier review runs passed 17 and then 22 tests. [Package evidence](../evidence/LAB-011/model-routing-package.json).
- `xcodebuild -project AppleNativeLab.xcodeproj -scheme LabMac-Core -destination platform=macOS -derivedDataPath build/DerivedData -only-testing:LabMacTests/ModelRoutingHostTests test -quiet`: passed. The result bundle summary confirmed 1 passed test, 0 failed or skipped. [Hosted fixture evidence](../evidence/LAB-011/model-routing-mac-host.json).
- `LAB_SIMULATOR_PREFIX="NL LAB-011-A" script/test.sh`: first attempt exited 2 before the script started: `labr-slot.sh: line 29: syntax error near unexpected token fi`. The executed full gate passed validators, validator self-tests, all package suites, and the Mac hosted stage, then exited 65 at iPhone test-runner launch: `Simulator device failed to launch org.example.lab011a.nativelab. No such process.` No shared queue infrastructure was edited.
- Remaining simulator stages used `python3 script/simulator.py create <platform> "NL LAB-011-A <platform>"`, `xcodebuild -project AppleNativeLab.xcodeproj -scheme <scheme> -destination "id=$simulator_id" -derivedDataPath build/DerivedData -collect-test-diagnostics never test -quiet`, and an EXIT trap calling `script/simulator.py delete` for that exact created ID. The fresh iOS retry (`LabPhone-Core`) passed 4 tests; `LabWatch` passed 115; `LabTV` passed 116, including its remote UI test. Result-bundle summaries confirmed zero failures or skips in these three stages. `simctl list devices` showed no remaining `NL LAB-011-A` simulators after cleanup.
- `python3 script/build_manifest.py`: passed, Source lane Release builds and policy checks for CoreLocal, SystemSurfaces, and Companions across Mac, iPhone, Watch, and TV. CloudOptional and FrontierOptional skipped because they have no schemes.
- Full-gate package totals: LabSupport 97, LabDomain 156, LabStore 44, LabStaging 40, LabDemo 119, LabFeatures 368 across 9 runs. Two existing known issues did not fail the LabFeatures stage. The Mac result summary reported Passed, 130 passing tests, 0 failures, and 2 skips.
- `python3 script/validate/all.py`: passed all 8 checks: 1952 local links, 109 tickets with 533 dependencies, 48 experiment specs (7 implemented / 41 specified), fresh catalog, 30 valid evidence records, and workflow policy.

No person drove the experiment’s UI and no live PCC request occurred.
