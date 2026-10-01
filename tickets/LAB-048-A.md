---
id: "LAB-048-A"
title: "Implement Commercial Frontier Desk"
status: "blocked"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-041-B"]
---

# LAB-048-A — Implement Commercial Frontier Desk

## Goal

Learn how a public app reaches privileged system surfaces without treating entitlements as magic flags.

## Authority and scope

Read the [governing specification](../experiments/LAB-048-commercial-frontier-desk.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** commercial-frontier-desk module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Provide three tiny independent lifecycle probes
3. PTT: model channel join/leave before any live APNs server
4. CarPlay: build an allowed-category simulator view
5. Screen Time: self-authorized demo with clear revocation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Missing managed approval does not break other targets. (Four platform builds/tests and independent unlinked SDK probes; see the recorded phone test exception below.)
- [x] No PTT wake is used for unrelated work. (Static review: no wake handler, background mode, APNs or audio path exists.)
- [x] Screen Time has a documented self-escape and never hides restrictions. (Simulated restriction/revocation tested; unreadable state is unavailable. Live system restrictions remain not-run.)
- [x] Fallback is usable: In-app protocol/lifecycle demonstrators labeled as simulations. (Nine domain tests and Mac/iPhone hosted replays; rendered controls were not manually driven.)
- [x] Sensitive operations share the domain authorization/receipt path. (Local lifecycle writes only; denied/replayed requests and hosted app-UI receipts tested. No live side effect.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Three bounded spikes, not three production products. Real PTT networking and managed distribution approvals are external gates.

**Research:** [S34](../docs/SOURCE_INDEX.md#s34), [S35](../docs/SOURCE_INDEX.md#s35), [S36](../docs/SOURCE_INDEX.md#s36).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**Delivered boundary:** three independent in-app lifecycle simulations and three isolated,
compile-only optional package targets. The optional signed PTT, CarPlay and Screen Time
executable hosts are not implemented. CarPlay's external-display simulator scene did not run;
its audio-category CPListTemplate factory typechecked only. The actual system portion is
blocked: no managed CarPlay approval, Family Controls provisioning/distribution permission,
or PTT capability/transport configuration was supplied. No account or service setup was attempted.
See [ADR-LAB-048](../docs/adr/ADR-LAB-048.md). The fallback's evidence does not prove these gates.

**Implementation:** `CommercialFrontier` owns typed capability cases, entitlement evidence,
a two-Boolean value snapshot, validated transitions, original audio list rows, fixed collection
and item IDs, a backend protocol and the main-actor desk. Each accepted lifecycle change commits
one `createItem` or revision-checked `updateItem` through the host's authorization-checked
OperationService and returns its immutable receipt. No store is exposed to the feature.
Duplicate requests reauthorize the recorded operation; the desk bounds its successful-request
cache to 256 entries. Reusing a request ID for another action is refused. That cache lasts only
one desk instance; persisted state survives reopening. Collection creation is a separate,
idempotent operation; cancellation/failure after it can leave an empty experiment collection.

PTT joins/leaves one fictional channel. CarPlay connects/disconnects an in-app audio list preview.
Screen Time models explicit individual authorization, one visible sample restriction and revoke.
Revoke and Reset probe clear both simulated authorization and restriction. Reset updates only
the selected fixed probe item; it does not delete other items, the collection or earlier receipts.
These local records are in the user namespace, so global Reset Demo leaves them alone.
Malformed owned records are refused rather than overwritten. Unreadable state is shown as
unavailable, not unrestricted, and a refused transition refreshes the saved state before retry.

**Surfaces and shared hooks:** `Apps/Shared/CommercialFrontier/` contains the observable session,
library backend and native Form. Mac opens a sheet with a Done/Escape control; iPhone uses a
NavigationLink. The single existing shared-view hook is `ExperimentDetailView`'s `FrontierLaunch`.
`Packages/LabFeatures/Package.swift` adds the fallback product/target, its tests and three unlinked
SDK probe targets. `project.yml` adds the fallback product to all five existing Mac/iPhone variants;
XcodeGen regenerated `AppleNativeLab.xcodeproj` on research and the result was copied back.
The two existing LabCatalog test files update the implemented inventory and state counts.
No entitlement, purpose string, target executable, profile, deployment floor or framework policy
was added. Watch and TV retain their existing catalog/readiness surfaces.

**SDK/source evidence:** Xcode 27.0 (27A266a), macOS 27.0 (26A425), SDK 27.0.
Apple S34/S35/S36 and the individual authorization walkthrough were consulted. The installed
headers/interfaces and exact compiled seams are in [the ledger](../docs/VERIFICATION_BOUNDARIES.md).
The initial PTT probe failed at `PTChannelDescriptor(name:image:)` because UIKit was not imported;
adding UIKit made the UIImage-typed initializer visible. This was an import requirement, not a
renamed symbol. Each optional target typechecked for arm64 iOS 26 using SDK 27. None runs in a host.

**Commands actually run, through `labr` on research:**

- `xcodebuild -version; sw_vers`, framework-header/interface `grep` and `sed`: recorded the above
  toolchain and join/leave, list template and individual authorization/revocation signatures.
- `set -e; sdk=$(xcrun --sdk iphoneos --show-sdk-path); for probe in FrontierPTTProbe FrontierCarPlayProbe FrontierScreenTimeProbe; do xcrun swiftc -typecheck -sdk "$sdk" -target arm64-apple-ios26.0 Packages/LabFeatures/Sources/$probe/*.swift; done`: first failed at the PTT initializer; all three passed after importing UIKit.
- `swift test --package-path Packages/LabFeatures --filter FrontierTests`: 7 tests passed initially;
  9 passed after stale/malformed-record cases were added; final narrow run passed 9 after no-op
  reset/revoke transitions were made unavailable.
- `script/generate_project.sh`: first invocation failed because XcodeGen was not on PATH.
  `export PATH=/opt/homebrew/bin:$PATH; script/generate_project.sh` passed; generated project copied
  back with `rsync -a --delete`. Catalog generation ran as part of that command.

**Not run:** physical-device PTT audio/APNs/wake, real CarPlay scene, live Screen Time authorization,
ManagedSettings shields or DeviceActivity monitoring/cleanup, managed distribution, optional
signed executable builds, a 26-family SDK compile, manual VoiceOver/Voice Control/Full Keyboard
Access, large-text/focus review, screenshots or recordings. No cloud, network transport, purchase,
account connection, credential creation or publication. The fallback installs no system restriction.
Before any live Screen Time host, implement and verify clearing every owned settings store and
stopping owned monitors before revocation; never shield the app or Settings.

**Next dependency-ready ticket:** [LAB-019-B](LAB-019-B.md). LAB-048-B remains dependent on
completion of this ticket's system-host work, not merely its fallback.

**Catalog follow-up:** the experiment is `implemented` for the fallback only, and catalog
JSON was regenerated with `python3 script/generate_catalog.py` on research and copied back.
The first full gate passed validators and all package suites except LabCatalogTests; its two
failures were the specified-count and explicit implemented-ID inventory assertions missed in
this change. Those expectations now name LAB-048 and count 19 specified / 29 implemented.
Two narrow reruns still observed old registry assertions: first the mirror source was stale,
then the source was correct but its compiled binary was reused. After committing the catalog
change and refreshing only the changed test-file timestamps, the focused
`swift test --package-path Packages/LabFeatures --filter LabCatalogTests` passed 14 tests in
2 suites. The full gate was restarted after that fix. No test was removed or relaxed.

**Hosted/full-gate results:** `LAB_SIMULATOR_PREFIX="NL LAB-048-A" script/test.sh` was run
through `labr` twice. The first failed at the missed catalog assertions described above.
The corrected run at `5d28e44-dirty` passed validators (8/8), validator self-tests (93), all
package suites and Mac hosted tests. The iPhone action failed (exit 65):
`SpeechTimelinePhoneTests/theOnDeviceRouteOrItsStatedFallbackRunsInsideTheApp(): Crash: NativeLab`.
This is the same existing failure recorded in LAB-041-B; no Speech Timeline file was changed.
The full gate is **failed**, not green. Watch, TV and release-manifest stages were skipped by
that run and were invoked separately below.

`xcresulttool get test-results tests` and `summary` confirm this ticket's
`FrontierHostTests/lifecycleReceiptsAndEscapePersistWithoutTouchingImports()` passed in both
Mac and iPhone actions. The Mac summary is Passed (198 tests: 194 passed, one expected failure,
three skipped); phone summary is Failed (12 passed, one failed). Both built app Info.plists
report `LabSourceRevision: 5d28e44-dirty`. Mac fixture host: Mac Studio / macOS 27.0 (26A425).
iPhone fixture host: iPhone 18 Pro simulator / iOS 27.0 (24A434). Neither harness presses or
inspects the rendered controls. The two hosted evidence records report only this ticket's
passing replay, not the full action as green.

**Remaining-stage command, through `labr`:**

```sh
set -e
for platform in watchOS tvOS; do
  sim=$(python3 script/simulator.py create "$platform" "NL LAB-048-A remaining $platform")
  trap "python3 script/simulator.py delete $sim" EXIT
  if [[ "$platform" == watchOS ]]; then scheme=LabWatch; else scheme=LabTV; fi
  xcodebuild -project AppleNativeLab.xcodeproj -scheme "$scheme" -destination "id=$sim"     -derivedDataPath build/DerivedData -collect-test-diagnostics never     LAB_SOURCE_REVISION=5d28e44-dirty test -quiet
  python3 script/simulator.py delete "$sim"
  trap - EXIT
done
python3 script/build_manifest.py
```

Watch and TV test actions passed in fresh watchOS 27.0 (24R362) and tvOS 27.0 (24J360)
simulators. Each created simulator was deleted before proceeding. This proves those existing
hosts continue building/testing without managed frontier approval, not frontier system surfaces.

**Acceptance evidence (fallback only):**

- Missing managed approval cannot enter the baseline: the independent unlinked SDK seams compile
  without it, and the four platform hosts build. No managed capability or entitlement was added.
- No PTT wake is used: no background mode, APNs handler, audio session or transport exists in the
  fallback or host hooks. The unlinked SDK seam only references foreground join/leave calls.
- Screen Time escape is visible: package `screenTimeEscapeClearsRestrictionsAndAuthorization`
  and both hosted replays clear the simulated restriction and authorization; the walkthrough
  documents clearing owned settings/monitors before any future live revocation and the independent
  Settings escape. Actual system restrictions and cleanup remain not-run.
- Usable labeled fallback: `threeIndependentLifecyclesAndReceipts` and both hosted replays complete
  the three independent probes and retain reopened state. Rendered/manual accessibility remains
  not-run; all actions use native textual controls.
- Sensitive local writes share the authorization/receipt path: package denied-first-write and
  duplicate-reauthorization cases, plus both hosted app-UI receipts. There is no live sensitive
  side effect; compile-only seams are not an authorized live path.

**Owner follow-up:** supply/manage approved optional system-host configurations before live
work, implement the explicit Screen Time cleanup adapter, and perform device and manual
accessibility qualification. Reproduce the existing Speech Timeline phone crash before claiming
a green repository gate. The ticket is `blocked` because its optional signed system hosts and
actual CarPlay simulator surface remain absent; the runnable fallback is `implemented`.

**Release/profile result:** the separate `python3 script/build_manifest.py` passed (exit 0) at
`5d28e44-dirty`, Release / Source lane. CoreLocal, SystemSurfaces and Companions built and passed
framework/entitlement policy checks; CloudOptional and FrontierOptional were skipped because no
scheme has a target attached. Watch summary: 115 passed; TV summary: 181 passed. Both fresh
simulators were deleted. No managed frontier framework or entitlement entered baseline products.

**Final optional compile check:** `set -e; xcodebuild -version; sdk=$(xcrun --sdk iphoneos --show-sdk-path); for probe in FrontierPTTProbe FrontierCarPlayProbe FrontierScreenTimeProbe; do xcrun swiftc -swift-version 6 -typecheck -sdk "$sdk" -target arm64-apple-ios26.0 Packages/LabFeatures/Sources/$probe/*.swift; done` passed all three probes, through `labr`. This checks Swift 6 mode using Xcode 27's compiler/SDK, not Xcode 26.6 or a 26-family SDK.

**Evidence:** [domain fixtures](../evidence/LAB-048/frontier-domain-fixtures.json),
[catalog fixtures](../evidence/LAB-048/frontier-catalog-fixtures.json),
[SDK seams](../evidence/LAB-048/frontier-sdk-probes.json),
[Mac hosted fixture](../evidence/LAB-048/frontier-mac-host.json),
[iPhone simulator fixture](../evidence/LAB-048/frontier-phone-simulator.json),
[gate and isolation result](../evidence/LAB-048/frontier-gate-isolation.json), and
[walkthrough](../evidence/LAB-048/README.md). Only original fixtures and source hashes were retained;
no device identifiers, screenshots, recordings, secrets or exported user data are in these records.

**Evidence validation correction:** the first final `python3 script/validate/all.py` returned 7/8 because the two simulator-path records omitted `execution.simulator`. Both now contain the observed iOS platform, device class and runtime version, without identifiers.

**Final validation:** `python3 script/validate/all.py` through `labr` passed 8/8 with all 60 evidence records valid and the catalog current after the metadata correction. `git diff --check` passed locally. Implementation is committed separately from catalog registration and this final evidence/completion record.
