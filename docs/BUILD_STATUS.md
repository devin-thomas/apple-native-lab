# Build status

This is the recorded build evidence for the lab. Update it from real runs only. A row describes what was run, not what the specification intends.

Last updated: 2026-09-29 (CORE-001, CORE-002, CORE-004).

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

Bundle identifiers derive from `LAB_BUNDLE_PREFIX` (default `org.example`), so developers change identity in `Config/Local.xcconfig` without editing source.

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

`script/test.sh` runs every check above that needs no device or signing.

## Not run

| Gate | Reason |
|---|---|
| Compile against a 26 SDK | No Xcode 26 on the primary Mac. The M1 compatibility Mac is the intended check. |
| Physical Watch install | No physical watchOS destination was available. See [DEVICE_SETUP](DEVICE_SETUP.md). |
| iPad, Apple TV | No device available for this project. |
| Any experiment | All 48 experiments remain `specified`. Installing the host proves the host only. |

## Known constraints

The hosts link AVFoundation, CoreBluetooth, FoundationModels, Speech, and (iPhone) ARKit and NearbyInteraction only to read capability status for the Readiness screen. No purpose strings or entitlements are declared, so no permission can be requested yet, and each experiment adds its own. Before any App Store or TestFlight upload, either declare purpose strings or move these probes behind a build profile (CORE-008): App Store processing can flag referenced privacy-sensitive APIs that lack purpose strings.

A free Personal Team can build CoreLocal to a device, but its profiles expire after seven days, it allows only a small number of developer apps per device, and it cannot use capabilities such as App Groups, iCloud, or Push. SystemSurfaces App Group staging and CloudOptional therefore need a paid team for on-device proof. The fallback paths must still work without them.
