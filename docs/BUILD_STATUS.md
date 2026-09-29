# Build status

This is the recorded build evidence for the lab. Update it from real runs only. A row describes what was run, not what the specification intends.

Last updated: 2026-09-29 (CORE-001 through CORE-004, CORE-006 through CORE-008; first CI run; compatibility Mac observed).

## Toolchain

Captured with `script/toolchain_report.sh` on the primary development Mac.

| Item | Observed |
|---|---|
| Host macOS | 27.0 (26A425) |
| Host chip | Apple M5 Max |
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 (swiftlang-6.4.0.34.1) |
| SDKs | iphoneos27.0, iphonesimulator27.0, macosx27.0, watchos27.0, watchsimulator27.0, appletvos27.0, appletvsimulator27.0, xros27.0 |
| XcodeGen | 2.46.0 (only needed to regenerate the committed project) |

## Deployment floor and feature levels

| Setting | Value | Evidence |
|---|---|---|
| iOS, macOS, watchOS floor | 26.0 | `LSMinimumSystemVersion`/`MinimumOSVersion` = 26.0 in built bundles |
| Swift language mode | 6 | project setting `SWIFT_VERSION = 6.0`; packages use tools version 6.2 |
| 27-generation adapters | compiled only against a 27 SDK | `OTHER_SWIFT_FLAGS = -DLAB_SDK_27` resolved for `macosx27.0`; Readiness shows the level at runtime |

`Config/Base.xcconfig` sets `LAB_SDK_27` per SDK, so an older Xcode builds the 26-family core with 27-generation adapters compiled out (ADR-009). **Not yet run:** a compile against a 26 SDK. This Mac has only Xcode 27 installed, and the compatibility Mac was offline when this was recorded.

## Schemes

| Scheme | Target | Platform | Profile | Signing default |
|---|---|---|---|---|
| `LabMac-Core` | `LabMac` + `LabMacTests` | macOS | CoreLocal | Sign to Run Locally, App Sandbox on |
| `LabPhone-Core` | `LabPhone` | iOS/iPadOS | CoreLocal | Automatic; device builds need `Config/Local.xcconfig` |
| `LabWatch` | `LabWatch` | watchOS | Companions | Automatic; installs directly to a paired Watch, not embedded in the iPhone app |

Each target takes its profile from the `Config/Profiles/<Profile>.xcconfig` file it attaches in `project.yml`, and that value reaches the `LabBuildProfile` Info.plist key. SystemSurfaces, CloudOptional, and FrontierOptional have their profile files but no targets or schemes yet; the release manifest reports them as skipped ([BUILD_AND_DISTRIBUTION](BUILD_AND_DISTRIBUTION.md#build-profiles)).

Bundle identifiers derive from `LAB_BUNDLE_PREFIX` (default `org.example`), and so do the App Group (`group.<prefix>.nativelab`), Keychain group (`<prefix>.nativelab.shared`), and CloudKit container (`iCloud.<prefix>.nativelab`) that optional profiles will use. Developers change identity in `Config/Local.xcconfig` without editing source. No target uses the shared identifiers yet.

## Evidence log

| Date | Check | Command | Result |
|---|---|---|---|
| 2026-09-29 | Catalog matches specs | `python3 script/generate_catalog.py --check` | passed (48 experiments) |
| 2026-09-29 | LabSupport unit tests | `swift test --package-path Packages/LabSupport` | 6 passed |
| 2026-09-29 | LabCatalog unit tests | `swift test --package-path Packages/LabFeatures` | 6 passed |
| 2026-09-29 | Mac hosted smoke tests | `xcodebuild … -scheme LabMac-Core test` | 3 passed (catalog in bundle, toolchain provenance, no-prompt device snapshot) |
| 2026-09-29 | iPhone simulator compile | `xcodebuild … -scheme LabPhone-Core -destination 'generic/platform=iOS Simulator' build` | succeeded |
| 2026-09-29 | Watch simulator compile | `xcodebuild … -scheme LabWatch -destination 'generic/platform=watchOS Simulator' build` | succeeded |
| 2026-09-29 | Clean checkout, no `Config/Local.xcconfig` | the three builds above from a fresh copy of tracked files | all succeeded with `org.example` identifiers |
| 2026-09-29 | Mac install | `script/install_mac.sh` | Release app installed to `~/Applications/Native Lab.app`, signature verified, launched |
| 2026-09-29 | iPhone install | `script/install_phone.sh <device-id>` | installed and launched on iPhone17,1 (iPhone 16 Pro), iOS 27.0 (24A5430a), Personal Team signing |
| 2026-09-29 | iPhone UI check | simulator iPhone18,3, iOS 27.0 | Catalog, experiment detail, and Readiness screens reviewed |
| 2026-09-29 | LabDomain unit tests (CORE-002) | `swift test --package-path Packages/LabDomain` | 49 passed in 9 suites, one test covering all 5 adapter kinds; 0 warnings on a clean build. Added to `script/test.sh` at integration |
| 2026-09-29 | LabDomain concurrency repeat (CORE-002) | the concurrency tests 100 times, then the full suite 50 times | 0 failures after a fix; before it, the duplicate-submission test failed 17 of 25 runs |
| 2026-09-29 | LabDomain iOS simulator compile (CORE-002) | `xcodebuild -scheme LabDomain -destination 'generic/platform=iOS Simulator' build` in `Packages/LabDomain` | succeeded, 0 warnings |
| 2026-09-29 | LabDomain watchOS simulator compile (CORE-002) | same, `generic/platform=watchOS Simulator` | succeeded, 0 warnings |
| 2026-09-29 | LabDomain tvOS simulator compile (CORE-002) | same, `generic/platform=tvOS Simulator` | succeeded, 0 warnings |
| 2026-09-29 | LabDomain macOS compile (CORE-002) | same, `platform=macOS` | succeeded, 0 warnings |
| 2026-09-29 | Store cannot be written around the service (CORE-002) | `swift build` of a throwaway package outside the repository that depends on LabDomain | failed as intended: an `AuthorizedCommit` cannot be created or decoded, a receipt cannot be created, and an `OperationRequest` cannot be decoded |
| 2026-09-29 | Existing automated checks still pass (CORE-002) | `script/test.sh` with LabDomain present | passed, unchanged: catalog check, 12 package tests, Mac hosted smoke tests, iPhone and Watch simulator compiles |
| 2026-09-29 | CORE-004 LabSupport unit tests | `swift test --package-path Packages/LabSupport` | 53 passed (6 existing, 47 capability and staging tests) |
| 2026-09-29 | CORE-004 LabSupport tests on the iOS simulator (manual) | `xcodebuild test -scheme LabSupport -destination 'platform=iOS Simulator,name=iPhone 17'` from `Packages/LabSupport` | 53 passed on iOS 27.0; the compiled probe set matches the iOS plan, and no simulated sensor reads as met |
| 2026-09-29 | CORE-004 LabSupport compiles per platform (manual) | `xcodebuild -scheme LabSupport -destination 'generic/platform=…' build` for iOS, iOS Simulator, watchOS, watchOS Simulator, tvOS Simulator | all succeeded with no warnings |
| 2026-09-29 | CORE-004 automated checks | `script/test.sh` | passed: catalog (48), LabSupport 53, LabCatalog 6, Mac hosted smoke 3, iPhone and Watch simulator compiles |
| 2026-09-29 | CORE-004 probe frameworks linked per target (manual) | `otool -L` on the Debug products | Mac: AVFoundation, CoreBluetooth, FoundationModels, Security, Speech. iPhone simulator: ARKit, AVFoundation, CoreBluetooth, FoundationModels, NearbyInteraction, Speech. Watch simulator: AVFAudio, CoreBluetooth, NearbyInteraction only |
| 2026-09-29 | CORE-004 Mac launch without prompts (manual) | `script/build_and_run.sh`, then `/usr/bin/log show --predicate 'process == "tccd"'` from launch; quit with `pkill -x NativeLab` | Readiness window restored at launch and probed. All 12 NativeLab TCC requests were `TCCAccessRequest` with `preflight=true` (status reads) and prompt policy 0; no prompt appeared. 2 ListenEvent preflights came at launch before any probe; 3 more came when an accessibility inspection attached |
| 2026-09-29 | CORE-004 Mac Readiness results (manual) | accessibility tree of the running Mac app | Camera unavailable (no camera found; entitlement and purpose string absent). Microphone, Speech recognition, Bluetooth, and Local network unavailable (entitlement or purpose string absent). On-device language model available, not device-verified. AR and Ultra Wideband listed as not on this platform. Rows expose a press action and their full gate text to VoiceOver |
| 2026-09-29 | CORE-004 iPhone Readiness (manual) | simulator iPhone 17, iOS 27.0 | All nine capabilities shown with gates and alternate routes; at the largest accessibility text size rows stack without truncation; no prompt appeared on screen (simulator TCC log not inspected) |
| 2026-09-29 | CORE-004 physical-device probes | none | not run |
| 2026-09-29 | LabStore unit tests (CORE-003) | `swift test --package-path Packages/LabStore` | 37 tests (70 cases with arguments) in 7 suites passed; 0 warnings on a clean build. Not yet part of `script/test.sh` |
| 2026-09-29 | LabDomain unit tests after CORE-003 | `swift test --package-path Packages/LabDomain` | 65 passed in 10 suites (CORE-002's 49 plus 16 namespace and Reset Demo tests); 0 warnings on a clean build |
| 2026-09-29 | Interrupted transaction (CORE-003) | `InterruptedTransactionTests` in the LabStore run | passed: stopping at each of 8 fault points before `COMMIT` left every row unchanged; a stop after `COMMIT` left the complete new state; a mid-commit copy of the database and log, with uncommitted pages on disk, recovered the old state |
| 2026-09-29 | Store repeat runs (CORE-003) | the full LabStore and LabDomain suites 30 times each; LabStore's concurrency, cross-process, and interruption tests 100 times | 0 failures |
| 2026-09-29 | Store mutation checks (CORE-003) | the LabStore tests against copies of the package, each with one guarantee removed | every mutation was caught: a deferred `BEGIN` (1 test failed), no transaction (8), an upsert clearing `extras` (1), deletable user rows (4) |
| 2026-09-29 | Cross-process lock (CORE-003) | `CrossProcessTests`, with `/usr/bin/sqlite3` 3.54.0 as the other process | passed: the other process got "database is locked" between the store's checks and writes, then wrote once the commit finished |
| 2026-09-29 | LabStore simulator and macOS compiles (CORE-003) | `xcodebuild -scheme LabStore -destination 'generic/platform=iOS Simulator' build` in `Packages/LabStore`, then the watchOS Simulator, tvOS Simulator, and `platform=macOS` destinations | all 4 succeeded, 0 warnings |
| 2026-09-29 | LabDomain compiles after CORE-003 | the same 4 destinations in `Packages/LabDomain` | all 4 succeeded, 0 warnings |
| 2026-09-29 | Existing automated checks (CORE-003) | `script/test.sh` | passed: catalog check; LabSupport 6, LabDomain 65, and LabFeatures 6 tests; Mac hosted smoke tests; iPhone and Watch simulator compiles. LabStore is not yet in the script |
| 2026-09-29 | CORE-007 LabSupport unit tests | `swift test --package-path Packages/LabSupport` | 97 passed in 13 suites (53 existing, 44 evidence and promotion); 0 warnings on a clean build with tests. Fixture path |
| 2026-09-29 | CORE-007 LabSupport tvOS simulator compile (manual) | `xcodebuild -scheme LabSupport -destination 'generic/platform=tvOS Simulator' build` in `Packages/LabSupport` | succeeded, 0 warnings |
| 2026-09-29 | CORE-007 repository validators | `python3 script/validate/all.py` | passed, 8 of 8 checks: 1710 local links in 205 Markdown files; 108 tickets with 527 dependencies and no cycles; 48 experiment specs; SPEC, Swift, and catalog state vocabularies agree; catalog fresh; 0 stored evidence records; 1 workflow within policy. Same result with Python 3.9 |
| 2026-09-29 | CORE-007 validator negative fixtures | `python3 -m unittest discover -s script/validate/tests` | 91 passed on Python 3.14 and 3.9. In temporary copies, a missing file, a link escaping the root, a missing anchor, a two-ticket cycle, a three-ticket cycle, and a self-dependency each failed with the file and line or the cycle path; `all.py` exited 1. A missing SPEC vocabulary exited 3 (blocked) |
| 2026-09-29 | CORE-007 workflow lint (static review) | `actionlint .github/workflows/ci.yml` (with shellcheck) | 0 errors |
| 2026-09-29 | CORE-007 CI steps rehearsed locally (manual) | each `run` step of `ci.yml` executed with bash on this Mac, emulating the Actions environment | 19 of 19 required checks passed with Xcode 27.0 (27A266a) selected over an installed 27.0 beta: validators, 91 self-tests, package tests 97, 49, and 6, Mac hosted tests 3, unsigned iPhone and Watch simulator builds. Feature level: macosx27.0, iphonesimulator27.0, and watchsimulator27.0, all with `LAB_SDK_27` compiled in. The 26 SDK compile, device qualification, and signed builds were listed as not run |
| 2026-09-29 | CORE-007 CI blocked path rehearsed (manual) | same, in a temporary copy with no Xcode visible to the selection step | selection blocked (exit 3); the 9 Xcode checks were skipped and reported not-run; summary "Overall: BLOCKED", exit 1 |
| 2026-09-29 | CORE-007 automated checks | `script/test.sh` | passed: catalog (48), LabSupport 97, LabDomain 49, LabFeatures 6, Mac hosted smoke 3, iPhone and Watch simulator compiles |
| 2026-09-29 | CORE-007 GitHub Actions run, including a fork pull request | none | not run: nothing was pushed from this environment |
| 2026-09-29 | CORE-007 compile against a 26 SDK | none | not run: only Xcode 27 is installed here. CI compiles with the runner's 26.x Xcode when one is installed |
| 2026-09-29 | CORE-008 project regeneration | `xcodegen generate --spec project.yml` (XcodeGen 2.46.0), run twice | second run byte-identical; targets attach `Config/Profiles/CoreLocal.xcconfig` (LabMac, LabMacTests, LabPhone) or `Companions.xcconfig` (LabWatch) |
| 2026-09-29 | CORE-008 automated checks | `script/test.sh` | passed: catalog (48), LabSupport 53, LabDomain 49, LabCatalog 6, Mac hosted smoke tests, iPhone and Watch simulator compiles, and the new release-manifest step |
| 2026-09-29 | CORE-008 clean copy, no `Config/Local.xcconfig`, no Git metadata | `xcodebuild` Debug builds of `LabMac-Core` (`platform=macOS`), `LabPhone-Core` (`generic/platform=iOS Simulator`), `LabWatch` (`generic/platform=watchOS Simulator`) | all succeeded with no compiler warnings; `org.example` identifiers; `LabBuildProfile` CoreLocal, CoreLocal, Companions; no purpose strings |
| 2026-09-29 | CORE-008 release manifest, clean copy | `script/build_manifest.py` | exit 0: CoreLocal built (`macosx27.0`, `iphonesimulator27.0`), Companions built (`watchsimulator27.0`), Xcode 27.0 (27A266a); SystemSurfaces, CloudOptional, and FrontierOptional skipped: no scheme builds a target attached to them yet; revision `unknown` (no Git metadata) |
| 2026-09-29 | CORE-008 Source lane leaves Info.plist unchanged | Release Info.plists from the clean copy compared with Release builds of 3d138f6 | only difference: the new `LabDistributionLane` key (`Source`) |
| 2026-09-29 | CORE-008 Store lane | `script/build_manifest.py --lane Store` | exit 0. Purpose strings: Mac camera, microphone, speech recognition, Bluetooth; iPhone the same plus Nearby Interaction; Watch microphone, Bluetooth, Nearby Interaction. None missing. No archive or upload was made |
| 2026-09-29 | CORE-008 linked frameworks per product | `otool -L` on the Debug debug dylibs and the Release executables | Mac: AVFoundation, CoreBluetooth, Foundation, FoundationModels, Security, Speech, SwiftUI. iPhone simulator: ARKit, AVFoundation, CoreBluetooth, Foundation, FoundationModels, NearbyInteraction, Speech, SwiftUI, UIKit (weak). Watch simulator: AVFAudio, CoreBluetooth, Foundation, NearbyInteraction, SwiftUI, UIKit (weak). All allowed by `Config/ProductPolicy.txt`; none unsupported on its platform; no private framework |
| 2026-09-29 | CORE-008 Mac entitlements | `codesign -dvvv --entitlements :-` on the Debug and Release `NativeLab.app` | ad hoc signature, no team. Entitlements: `com.apple.security.app-sandbox` (the only declared key) and `com.apple.security.get-task-allow` (added by Xcode for local signing). Release carries the hardened-runtime flag; the Debug build's flags show ad hoc only |
| 2026-09-29 | CORE-008 manifest refuses bad products (throwaway copies, not committed) | `script/build_manifest.py` after adding an App Group entitlement to the Mac host, marking ARKit unsupported on iOS, removing ARKit's allowance, blanking the Bluetooth purpose string in the Store lane, or embedding a SystemSurfaces widget extension with an App Group entitlement in `LabPhone` | each run exited 1 with CoreLocal `failed` and the matching reason (for the widget: another profile's target in the scheme, an embedded bundle from SystemSurfaces, WidgetKit and the App Group entitlement not allowed in CoreLocal). Xcode refused to sign the Mac App Group entitlement without a development certificate; the iOS simulator build of the widget signed its App Group entitlement with no team |
| 2026-09-29 | CORE-008 identifiers follow the prefix | `xcodebuild -showBuildSettings` with a local file setting only `LAB_BUNDLE_PREFIX = com.example.override` | App Group `group.com.example.override.nativelab`, Keychain group `com.example.override.nativelab.shared`, CloudKit `iCloud.com.example.override.nativelab`; the manifest recorded "local override (not recorded)" and never the prefix |
| 2026-09-29 | CORE-008 Store archive, export, upload; device builds of optional profiles | none | not run: no target exists in the optional profiles, and a Store upload needs a paid team and publication approval |
| 2026-09-29 | First GitHub Actions run | CI run 36625649106 on a GitHub-hosted `macos-26` runner at 04a56df | passed, every step. The runner had no Xcode 27, so it selected Xcode 26.6 (17F113) with 26.5 SDKs: validators 8/8, validator self-tests, LabSupport, LabDomain, LabStore, and LabFeatures tests, Mac hosted tests, and unsigned iPhone and Watch simulator builds, all at the 26-family feature level with `LAB_SDK_27` compiled out |
| 2026-09-29 | Compatibility Mac observed | SSH over the tailnet | Apple M1, 8 GB memory, macOS 27.0 (26A5388g). Xcode 26.6 (17F113) installed, but its license has not been accepted, so the active developer directory is Command Line Tools |
| 2026-09-29 | Packages compile on the compatibility Mac | `swift build --package-path Packages/<each>` with Command Line Tools Swift 6.2.3, from a fresh clone of 04a56df | LabSupport, LabDomain, LabStore, LabFeatures: build complete, no warnings. `swift test` there fails only because Command Line Tools lack the `Testing` module; package tests need Xcode |
| 2026-09-29 | CORE-006 LabDomain unit tests | `swift test --package-path Packages/LabDomain` | 139 passed in 18 suites: 65 existing, and 74 for staging policy, records, grants, adoption, instruction injection, diagnostics, and logging discipline. 0 warnings on a clean build with tests. Fixture path |
| 2026-09-29 | CORE-006 LabStaging unit tests | `swift test --package-path Packages/LabStaging` | 40 passed in 6 suites; the 22 hostile names and 10 tampering cases run as arguments. 0 warnings on a clean build with tests. Fixture path: real files in a temporary folder on macOS |
| 2026-09-29 | CORE-006 system log readback | `DiagnosticsTests` and `DiagnosticsPrivacyTests`, reading `OSLogStore(scope: .currentProcessIdentifier)` | passed: each stored message equals the event's metadata line. No sentinel file name, token, prompt, content, host, or path appears in any event, sink, export, error text, quarantine reason file, or system log entry |
| 2026-09-29 | CORE-006 repeat runs | both suites 15 times each | 0 failures |
| 2026-09-29 | CORE-006 mutation checks | the relevant tests against copies of the packages, each with one guarantee removed | 11 of 11 caught. The mutations: no cancellation check after a stream ends; no overlap check; the inflater limit ignored or removed; the writer budget removed; hard-linked staged files accepted; duplicate JSON keys accepted; unknown record fields accepted; grant expiry ignored; the policy allowing commits without a live grant; lookalike separators accepted. The inflater mutation survived at first, because the file writer also bounds each entry. Direct tests of each bound now catch it |
| 2026-09-29 | CORE-006 simulator compiles | `xcodebuild -scheme LabDomain` and `-scheme LabStaging`, `-destination 'generic/platform=iOS Simulator'` and the watchOS and tvOS simulators, each in its package | all 6 succeeded, 0 warnings |
| 2026-09-29 | CORE-006 repository validators | `python3 script/validate/all.py` | passed, 8 of 8: 1,718 local links in 208 Markdown files |
| 2026-09-29 | CORE-006 automated checks | `script/test.sh` | passed: validators and 91 self-tests; LabSupport 97, LabDomain 139, LabStore 37, and LabFeatures 6 tests; Mac hosted smoke tests; iPhone and Watch simulator compiles. LabStaging is not yet in the script |
| 2026-09-29 | CORE-006 share extension, App Group, and data protection | none | not run: no share extension target exists (LAB-007-A), App Groups need a paid team, and `completeUnlessOpen` protection is not enforced on macOS or in the simulator |
| 2026-09-29 | CORE-005 project regeneration | `xcodegen generate --spec project.yml` (XcodeGen 2.46.0), run twice | second run byte-identical. Only change: LabMac and LabPhone depend on LabDomain and LabStore and bundle `Fixtures/demo/seed.json`; Info.plists unchanged |
| 2026-09-29 | CORE-005 LabFeatures tests | `swift test --package-path Packages/LabFeatures` | 14 passed (6 catalog, 8 registry): every catalog experiment registered once, every fallback identical to its spec's Fallback paragraph, source links resolve to files in the repository, six distinct states, a missing, unknown, or duplicate registration refuses to load |
| 2026-09-29 | CORE-005 registry drift check (throwaway copy, not committed) | the same tests after shortening one compiled fallback | `everyFallbackMatchesItsSpecification` failed as intended; the other 13 passed |
| 2026-09-29 | CORE-005 Mac hosted tests | `xcodebuild … -scheme LabMac-Core test` | 12 passed: the 3 smoke tests and 9 host tests. In a temporary store inside the sandboxed app: first run seeds 3 collections and 12 items through one Reset Demo receipt (15 created); a later launch never resets; archive offers an undo that runs as its own request; Reset Demo restores an archived sample at revision 3; a stale undo becomes a conflict receipt and changes nothing; a non-store file is refused unchanged; a build without its seed writes nothing |
| 2026-09-29 | CORE-005 Mac launch (manual) | `script/build_and_run.sh`, System Events UI scripting and the Accessibility API; quit with `pkill -x NativeLab` | first launch created the store and seeded 12 samples. Menus read from the running app: Search… ⌘F, Show Receipt Inspector ⌥⌘I, Lab Collection ⌘1, All Experiments ⌘2, First Release Journey ⌘3, Reset Demo… ⇧⌘R, Show Latest Receipt ⌥⌘L, Readiness ⇧⌘0, Settings ⌘,. Pressed: each shortcut; Escape and Cancel dismissed Reset Demo with no receipt; confirmed resets from the menu and from Settings; archive, undo, and a stale undo (conflict, expected revision 2, found 3); search; sample selection with arrow keys. Every control had an accessible label |
| 2026-09-29 | CORE-005 Mac offline and entitlements | `codesign -d --entitlements :-`; source search for network APIs | app declares only the App Sandbox (no network entitlement); no source uses a network API. The only URL is the public spec link, opened on request |
| 2026-09-29 | CORE-005 iPhone journey, default text size (manual) | a UI test harness in a throwaway copy of this branch (not committed), simulator iPhone 17e, iOS 27.0 | passed: catalog, state legend, experiment detail, collection, archive, receipt with undo, undo, Reset Demo cancel and confirm, receipts list, Import to LAB-007, Readiness. Each screen's primary action was on screen and hittable without scrolling |
| 2026-09-29 | CORE-005 iPhone journey, largest text size (manual) | the same harness after `xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`, reset to `large` afterwards | passed after fixes found by this run: pinned the sample action, stacked the row metadata, capped the pinned bar's text at accessibility size 2 with the large content viewer, moved the undo offer above the receipt details, and used an alert so Cancel is visible. The undo offer needs one scroll at this size |
| 2026-09-29 | CORE-005 automated checks | `script/test.sh` | failed at the last step only: validators 8/8, validator self-tests, LabSupport 97, LabDomain 65, LabStore 37, LabFeatures 14, Mac hosted 12, iPhone and Watch simulator compiles all passed; the release manifest failed CoreLocal because LabMac and LabPhone now link CryptoKit (LabStore `DemoFixture`), which `Config/ProductPolicy.txt` does not allow |
| 2026-09-29 | CORE-005 policy fix (throwaway copy, not committed) | `script/build_manifest.py` with `link CoreLocal macos CryptoKit` and `link CoreLocal ios CryptoKit` added | exit 0: CoreLocal and Companions built. Linked frameworks match the CORE-008 row plus CryptoKit on the Mac and iPhone |
| 2026-09-29 | CORE-005 device, VoiceOver, keyboard, and motion passes | none | not run: no physical device run; VoiceOver speech, Full Keyboard Access, Reduce Motion, and Increase Contrast need system settings this run did not change |

`script/test.sh` runs every check above that needs no device or signing.

## Not run

| Gate | Reason |
|---|---|
| Xcode build and tests on the compatibility Mac itself | Its Xcode 26.6 license has not been accepted. The 26-family level is already proven in CI with the same Xcode build (17F113), and its packages compile there with Swift 6.2.3. |
| Physical Watch install | No physical watchOS destination was available. See [DEVICE_SETUP](DEVICE_SETUP.md). |
| iPad, Apple TV | No device available for this project. |
| Any experiment | All 48 experiments remain `specified`. Installing the host proves the host only. |

## Known constraints

The hosts link AVFoundation, CoreBluetooth, FoundationModels, Speech, and (iPhone) ARKit and NearbyInteraction only to read capability status for the Readiness screen. A Source-lane build, the default, declares no purpose strings and no entitlement beyond the Mac App Sandbox, so no permission can be requested yet, and each experiment adds its own. App Store processing can flag referenced privacy-sensitive APIs that lack purpose strings, so App Store and TestFlight archives use the Store lane (`LAB_DISTRIBUTION_LANE = Store`, CORE-008), which declares honest purpose strings for exactly the frameworks each host links; `script/build_manifest.py --lane Store` fails a product that misses one. The probes are not compiled out. Store-lane Info.plist generation also renames the Mac bundle name to `NativeLab` and adds two Xcode default keys; see [BUILD_AND_DISTRIBUTION](BUILD_AND_DISTRIBUTION.md#purpose-strings-and-the-store-lane). No Store archive or upload has been made.

A free Personal Team can build CoreLocal to a device, but its profiles expire after seven days, it allows only a small number of developer apps per device, and it cannot use capabilities such as App Groups, iCloud, or Push. SystemSurfaces App Group staging and CloudOptional therefore need a paid team for on-device proof; CoreLocal never does, and simulator builds of every profile need no team. The fallback paths must still work without them.

Linked frameworks and entitlements are checked per profile and platform against `Config/ProductPolicy.txt` whenever the release manifest runs. A locally signed Mac build also carries `com.apple.security.get-task-allow`, which Xcode adds for development signing.
