# Build status

This is the recorded build evidence for the lab. Update it from real runs only. A row describes what was run, not what the specification intends.

Last updated: 2026-09-29 (CORE-001).

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

`script/test.sh` runs every check above that needs no device or signing.

## Not run

| Gate | Reason |
|---|---|
| Compile against a 26 SDK | No Xcode 26 on the primary Mac. The M1 compatibility Mac is the intended check. |
| Physical Watch install | No physical watchOS destination was available. See [DEVICE_SETUP](DEVICE_SETUP.md). |
| iPad, Apple TV | No device available for this project. |
| Any experiment | All 48 experiments remain `specified`. Installing the host proves the host only. |

## Known constraints

A free Personal Team can build CoreLocal to a device, but its profiles expire after seven days, it allows only a small number of developer apps per device, and it cannot use capabilities such as App Groups, iCloud, or Push. SystemSurfaces App Group staging and CloudOptional therefore need a paid team for on-device proof. The fallback paths must still work without them.
