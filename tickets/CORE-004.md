---
id: "CORE-004"
title: "Build capability probes and permission staging"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001"]
---

# CORE-004 — Build capability probes and permission staging

## Goal

Replace platform-name assumptions with inspectable readiness and a useful fallback.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Packages/LabSupport capability registry and host capability UI.

## Implementation steps

1. Model hardware, OS/API, asset, permission, entitlement, service, and verification gates separately
2. Implement no-prompt startup probes where supported and unknown state where not queryable
3. Request permissions only from an explicit feature action
4. Expose an explainable unavailable state and fallback routing

## Acceptance criteria

- [x] Launching the core does not trigger a permission storm. (Mac: every TCC request at launch was a preflight status read; see the evidence log.)
- [x] Unknown support is never shown as verified readiness. (Exhaustive gate-combination test; readiness has no verified value.)
- [x] Denied permissions produce the documented alternate route. (Unit tests with fakes. A live denial was not exercised: this build cannot ask, because the hosts declare no purpose strings.)
- [x] Probes cannot import unsupported frameworks into another platform target. (Compiled for iOS, macOS, watchOS, and tvOS; linked frameworks inspected per target.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:** `Packages/LabSupport/Sources/LabSupport/Capabilities/` (new), five new test files in `Packages/LabSupport/Tests/LabSupportTests/`, `Apps/Shared/ReadinessView.swift`, `Apps/Shared/CapabilityBoard.swift` and `Apps/Shared/CapabilityRow.swift` (new), `docs/BUILD_STATUS.md` (evidence rows). No change to `project.yml`, entitlements, or Info.plist.

**What exists now:**

- Seven gate kinds (hardware, OS and API, on-device asset, permission, entitlement, service, verification), each with its own state: met, needs action, denied, restricted, unmet, or unknown. The entitlement gate covers Mac sandbox and hardened-runtime entitlements and the Info.plist purpose strings the system requires before it will prompt.
- Readiness is combined with fixed precedence: unmet, then denied or restricted, then unknown, then needs action, then available. Verification never counts toward availability, readiness has no verified value, and no probe can satisfy the verification gate.
- Nine no-prompt probes behind a read-only `CapabilitySource` protocol. `LiveCapabilitySource` guards every import with both `canImport` and `os`, because `canImport` alone is not enough in the 27.0 SDKs (see the notes below).
- `PermissionStager` (an actor) is the only holder of `PermissionRequesting`. It asks only for a `FeatureAction`. It does not ask again after a denial, falls back instead of asking when a purpose string or Mac entitlement is missing, leaves session-only permissions (Bluetooth, Nearby Interaction, local network) to the system, and merges concurrent requests into one prompt.
- Each capability has a documented alternate route taken from its experiment spec, shown whenever it is not available.
- The Readiness screen on Mac and iPhone shows each capability's readiness, the gates that decided it, every gate on request, and the alternate route. States use text plus a symbol. Rows are plain buttons with a value and a hint for VoiceOver, and **Probe Again** (⌘R) re-reads status. The Watch host is unchanged; it links the watchOS probes but shows none.

**Probes and SDK symbols** (all available at the 26.0 floor; none needed `if #available` or a 27-generation guard):

| Capability | Platforms compiled | Symbols read |
|---|---|---|
| Camera | iOS, macOS | `AVCaptureDevice.authorizationStatus(for: .video)`, `AVCaptureDevice.default(for: .video)` |
| Microphone | iOS, macOS; watchOS | `AVCaptureDevice.authorizationStatus(for: .audio)`, `AVCaptureDevice.default(for: .audio)`; on watchOS `AVAudioApplication.shared.recordPermission`, `AVAudioSession.sharedInstance().isInputAvailable` |
| Speech recognition | iOS, macOS | `SFSpeechRecognizer.authorizationStatus()`, `SpeechTranscriber.isAvailable`, `SpeechTranscriber.supportedLocale(equivalentTo:)`, `SpeechTranscriber.installedLocales` |
| On-device language model | iOS, macOS | `SystemLanguageModel.default.availability`, `SystemLanguageModel.supportsLocale(_:)` |
| AR world tracking | iOS | `ARWorldTrackingConfiguration.isSupported` (plus camera status) |
| AR scene reconstruction | iOS | `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)` (plus camera status) |
| Ultra Wideband ranging | iOS, watchOS | `NISession.deviceCapabilities` (`supportsPreciseDistanceMeasurement`, `supportsDirectionMeasurement`) |
| Bluetooth | iOS, macOS, watchOS, tvOS | `CBManager.authorization` (class property; no manager is created) |
| Local network | iOS, macOS, tvOS | none: not queryable, reported as unknown with the reason |
| Mac entitlements | macOS | `SecTaskCreateFromSelf`, `SecTaskCopyValueForEntitlement` |

**Evidence:** see the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). In summary: `swift test --package-path Packages/LabSupport` passed 53 tests on macOS, and the same 53 passed on the iOS 27.0 simulator. `script/test.sh` passed. LabSupport compiled for iOS, the iOS simulator, watchOS, the watchOS simulator, and the tvOS simulator. The Mac app launched with its Readiness window restored and made only preflight TCC requests.

**Not run:** probe results on any physical iPhone, iPad, Watch, or Apple TV; LabSupport tests on a watchOS or tvOS simulator (no runtime installed, so compile only); a live permission request and denial (no host declares a purpose string, so the stager falls back before asking); a compile against a 26 SDK.

**Specification notes:**

- `canImport` is not a platform guard in the 27.0 SDKs. The macOS SDK ships an ARKit module without `ARWorldTrackingConfiguration`, the watchOS and tvOS SDKs ship FoundationModels with `SystemLanguageModel` marked unavailable, and the tvOS SDK ships Speech with `SFSpeechRecognizer` unavailable. NearbyInteraction headers exist in the macOS SDK, but `NISession` is marked unavailable there.
- The SDKs have no API that reads local network or Nearby Interaction permission in advance, and none that reads the Bluetooth power state without creating a manager, which can prompt. These gates stay unknown on purpose. The security entitlement API (`SecTask`) is macOS-only.
- The iOS 27.0 simulator reports `supportsPreciseDistanceMeasurement == true`. A positive simulator reading for a physical sensor is shown as unknown, never met.
- Because no host declares a purpose string or device entitlement, permission-gated capabilities read "Unavailable: Entitlement" in this build. That is accurate: this build cannot ask. Each experiment adds its own strings and entitlements with its profile (CORE-008).
- The CORE-001 record says no optional framework is linked. Status-only probes now link AVFoundation, Speech, FoundationModels, and CoreBluetooth on the Mac; add ARKit and NearbyInteraction on iPhone; and link AVFAudio, CoreBluetooth, and NearbyInteraction on the Watch. No entitlement or capability comes with them. Before any App Store or TestFlight upload, check whether referencing these APIs without purpose strings is flagged. CORE-008 can move probes behind profiles if so.
- ADR-005 is implemented as written, so no new decision record was needed.

**Next dependency-ready tickets:** CORE-008, which depends only on CORE-001 and CORE-004. CORE-007 and CORE-005 also wait on CORE-002 (and CORE-005 on CORE-003).
