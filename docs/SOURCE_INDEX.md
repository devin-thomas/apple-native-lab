# Primary-source index


Research snapshot: 2026-09-29.


**Reviewed** means the cited primary-source content was inspected while preparing this plan. It does not mean compiled, device-tested, or guaranteed current at implementation time. **Reference** means an official entry point is supplied for the builder's next research step; its detailed contents/availability were not fully audited in this pack. URLs are the durable citations; refresh them before implementing a version-sensitive API.


## S01

**App Intents foundations** — reviewed

Source: [App Intents foundations](https://developer.apple.com/videos/play/wwdc2025/244/)

Use in this plan: Typed actions and entities; OS entry points.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-29, Xcode 27.0 with the macOS and iOS 27.0 SDKs): the confirmation, disambiguation, `supportedModes`, and `AppIntentsPackage` symbols Action Atlas uses, with their declared availability, are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger). They were compiled for macOS and iOS and run in the iOS simulator's Shortcuts app, not on a device.

## S02

**Siri and App Schemas, WWDC26** — reviewed

Source: [Siri and App Schemas, WWDC26](https://developer.apple.com/videos/play/wwdc2026/240/)

Use in this plan: Schema adoption, content transfer, and onscreen associations.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30): the iOS 27.0 SDK's `AppSchema` domains were read and none was adopted for a lab sample. `View.appEntityIdentifier(_:)` associates one sample with its view ([installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger)).

Installed SDK check (2026-09-30, Xcode 27.0 (27A266a), macOS and iOS 27.0 SDKs, for LAB-006-A): `IndexedEntity` and `CSSearchableIndex.indexAppEntities` / `deleteAppEntities(identifiedBy:ofType:)` are in App Intents (macOS 15.0, iOS 18.0, visionOS 2.0) and absent from the watchOS and tvOS interfaces. No entitlement. See the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger).

## S03

**App Shortcuts HIG** — reviewed

Source: [App Shortcuts HIG](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts)

Use in this plan: Up to ten curated App Shortcuts; distinguish the larger action library and platform-specific support.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30): `AppShortcutsProvider` is adopted by LAB-003-A as `NativeLabAppShortcuts` with six curated entries ([installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger)).

## S04

**Shortcuts, WWDC26** — reviewed

Source: [Shortcuts, WWDC26](https://developer.apple.com/videos/play/wwdc2026/310/)

Use in this plan: Storage and model actions; stable cross-device entity identifiers.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30): LAB-003-A does not call Shortcuts Storage; recipes bind lab-owned entity UUIDs and redact secrets on export. The iOS 27.0 AppIntents.swiftinterface has no type named Shortcuts Storage; durable identity is `PersistentlyIdentifiable` ([installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger)).

## S05

**AppIntentsTesting, WWDC26** — reviewed

Source: [AppIntentsTesting, WWDC26](https://developer.apple.com/videos/play/wwdc2026/295/)

Use in this plan: Integration tests run through system infrastructure; same signing team requirement.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-29): Xcode 27.0 ships `AppIntentsTesting` as a test-only framework for every platform, available from the 27.0 OS releases. No system-path test has run: this source says it needs the app's signing team, and no test target is set up for it ([installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger)).

## S06

**Foundation Models, WWDC26** — reviewed

Source: [Foundation Models, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)

Use in this plan: New model modalities, provider abstraction, tools, profiles, and evaluation tooling.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-29, Xcode 27.0 (27A266a), from the macOS 27.0 SDK's `FoundationModels.swiftinterface`, for LAB-010-A). Availability is the SDK's declaration. Every symbol below is unavailable on tvOS. No entitlement is needed: the model ran inside the sandboxed Mac app, whose only entitlement is App Sandbox.

| Symbol LAB-010 uses | Installed signature | Declared availability |
|---|---|---|
| `SystemLanguageModel` | `final class SystemLanguageModel: Sendable`; `static var default`; `var availability: Availability`, which is `.available` or `.unavailable(UnavailableReason)` with `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, and `.modelNotReady`; `func supportsLocale(_ locale: Locale = Locale.current) -> Bool` | iOS, macOS, visionOS 26.0; watchOS unavailable |
| `SystemLanguageModel.variant` | `var variant: Variant`, with `displayName`; `.core3` and `.coreAdvanced3` | iOS, macOS, visionOS 27.0; read under `#if compiler(>=6.4)` for evidence only |
| `LanguageModelSession` | `convenience init(model: SystemLanguageModel = .default, tools: [any Tool] = [], instructions: String? = nil)`. The `model: some LanguageModel` initializers are 27.0 and not used. | iOS, macOS, visionOS 26.0; watchOS 27.0 |
| Guided generation | `respond(to: String, schema: GenerationSchema, includeSchemaInPrompt: Bool = true, options: GenerationOptions) async throws -> Response<GeneratedContent>`, then `Generable.init(_: GeneratedContent)`. `respond(to:generating:includeSchemaInPrompt:options:)` is the static-schema form. 27.0 adds overloads that take `contextOptions:` and `metadata:`, and `streamResponse`; neither is used. | 26.0, as above |
| `@Generable`, `@Guide` | `@Generable(description:)`; `@Guide(description:_:)` with `GenerationGuide` values `.anyOf([String])`, `.maximumCount(_:)`, `.count(_:)`, and `.element(_:)` | 26.0, as above |
| Runtime schema | `GenerationSchema(type:description:properties:)` with `GenerationSchema.Property(name:description:type:guides:)`, which narrows the sample title to the offered titles | 26.0, as above |
| `GeneratedContent` | `init(json: String) throws` and `var isComplete: Bool`. Cut-off JSON parses, so `isComplete` is required. | 26.0, as above |
| `Tool` | `protocol Tool<Arguments, Output>: Sendable` with `name`, `description`, `parameters: GenerationSchema`, and `@concurrent func call(arguments: Arguments) async throws -> Output`. `Arguments` must be `@Generable`; a `String` argument is marked unavailable. | iOS, macOS, visionOS 26.0; watchOS 27.0 |
| `GenerationOptions` | `init(samplingMode:temperature:maximumResponseTokens:)`, back-deployed to 26.0; `SamplingMode.greedy`. `toolCallingMode` is 27.0 and not used. | 26.0 |
| Errors | `LanguageModelSession.GenerationError` is 26.0 and deprecated in 27.0. Its 27.0 replacements are `LanguageModelError`, `SystemLanguageModel.Error`, `GeneratedContent.ParsingError`, and `LanguageModelSession.Error`. Both families are mapped by type and case. | 26.0 and 27.0 |

Demonstrated on the development Mac (Apple M5 Max, macOS 27.0, en_US):

- The model's state: `availability` was `.available`, `supportsLocale()` was true, `variant.displayName` was "AFM 3 Core Advanced", and `contextSize` was 8192.
- The live draft ran in a `swift test` process and inside the sandboxed Mac app.
- The iOS 27.0 simulator on this Mac also reported the model available and ran it.
- No physical iPhone was used.

Uncertain: which variant and availability other devices report, and the 26-family SDK compile. The output also differs between processes on the same Mac: see the [LAB-010-A](../tickets/LAB-010-A.md) record.

## S07

**Private Cloud Compute eligibility** — reviewed

Source: [Private Cloud Compute eligibility](https://developer.apple.com/private-cloud-compute/). Refreshed 2026-09-30 for LAB-011-A alongside [server-side intelligence](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) and the [Boolean entitlement key](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute).

Use in this plan: Small Business Program, download threshold, entitlement, and permitted distribution gates.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 (27A266a), macOS 27.0 SDK `FoundationModels.swiftinterface`, for LAB-011-A). Availability is the SDK's declaration.

| Symbol LAB-011 uses or gates on | Installed signature | Declared availability |
|---|---|---|
| `PrivateCloudComputeLanguageModel` | `final class PrivateCloudComputeLanguageModel: Sendable`; `convenience init()`; `var availability`; `var quotaUsage`; `var isAvailable` | iOS, macOS, visionOS, watchOS 27.0; `@available(tvOS, unavailable)` |
| `Availability` | `.available` or `.unavailable(UnavailableReason)` with `.deviceNotEligible`, `.systemNotReady` | 27.0, as above |
| `QuotaUsage` | `status` (`.belowLimit(BelowLimit)` with `isApproachingLimit`, or `.limitReached`); `isLimitReached`; optional `limitIncreaseSuggestion`, `resetDate` | 27.0, as above |
| Errors | `.networkFailure`, `.quotaLimitReached`, `.serviceUnavailable` | 27.0, as above |
| Entitlement (not an SDK symbol) | `com.apple.developer.private-cloud-compute` | Managed; Small Business Program, download threshold, account assignment, and App Store / TestFlight / ad hoc distribution ([S07] page) |

LAB-011's package reads availability and quota behind `#if compiler(>=6.4)` and `#available(iOS 27.0, macOS 27.0, *)` on iOS and macOS hosts. CoreLocal does not declare the entitlement; program and distribution gates stay closed. No live PCC send ran: CoreLocal uses `RefusingCloudTransport`. A source build is not PCC-eligible by default.

Earlier note (2026-09-29): LAB-010 never references `PrivateCloudComputeLanguageModel`; its `PrivacyAndRouteTests` still fails if Typed Local Intelligence does.

## S08

**Xcode** — reviewed

Source: [Xcode](https://developer.apple.com/xcode/)

Use in this plan: Xcode 27 toolchain family; exact patch must be pinned during bootstrap.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S09

**Apple Intelligence hardware and availability** — reference

Source: [Apple Intelligence hardware and availability](https://support.apple.com/en-us/121115)

Use in this plan: Runtime, language, region, and hardware eligibility must be checked.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-29): LAB-010 reads eligibility at run time, through the CORE-004 probe and again for every request. It reads `SystemLanguageModel.default.availability` and `supportsLocale(_:)`, never the device name ([S06](#s06)).

## S10

**SpeechAnalyzer, WWDC25** — reviewed

Source: [SpeechAnalyzer, WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/)

Use in this plan: On-device transcription with separately managed assets and time-aligned results.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the macOS and iOS 27.0 SDKs): the `SpeechAnalyzer`, `SpeechTranscriber`, and `AssetInventory` symbols Speech Timeline uses, with their declared availability, are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#speech-lab-013). They were compiled for macOS and iOS. The transcriber ran on the development Mac, in a test process and in the sandboxed app, on speech this Mac's synthesizer produced; the iOS 27.0 simulator reports it unavailable. No microphone, physical iPhone, or model download was used.

## S11

**Core Transferable representations** — reviewed

Source: [Core Transferable representations](https://developer.apple.com/documentation/CoreTransferable/TransferRepresentation)

Use in this plan: Multiple import/export representations for typed items.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S12

**Drag sources** — reviewed

Source: [Drag sources](https://developer.apple.com/documentation/swiftui/making-a-view-into-a-drag-source)

Use in this plan: Transferable objects can participate in drag-and-drop.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S13

**Share extensions** — reference

Source: [Share extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)

Use in this plan: Share-extension integration reference; check current extension lifecycle guidance.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S14

**File Provider** — reference

Source: [File Provider](https://developer.apple.com/documentation/fileprovider)

Use in this plan: Separate extension and provider lifecycle research.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S15

**CloudKit sync engine** — reviewed

Source: [CloudKit sync engine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)

Use in this plan: Periodic synchronization is not a real-time transport; private/shared database scope.

Installed SDK (LAB-017-A, 2026-09-30, Xcode 27.0 27A266a, iOS 27.0): `CKSyncEngine`, `CKSyncEngine.Configuration.init(database:stateSerialization:delegate:)`, `fetchChanges(_:)`, and `sendChanges(_:)` are available from macOS 14.0 and iOS 17.0. `CKSyncEngine.Event.accountChange` includes `signIn`, `signOut`, and `switchAccounts`. `CKAccountStatus.temporarilyUnavailable` is available from macOS 12.0 and iOS 15.0. CoreLocal does not import or link CloudKit. The ledger's profile is a directory, and `RecordScope` has no public-database case.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S16

**Group Activities** — reference

Source: [Group Activities](https://developer.apple.com/documentation/groupactivities)

Use in this plan: SharePlay session and messaging reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S17

**Wi-Fi Aware, WWDC25** — reviewed

Source: [Wi-Fi Aware, WWDC25](https://developer.apple.com/videos/play/wwdc2025/228/)

Use in this plan: Pairing, device capability checks, and local peer communication.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S18

**Nearby Interaction** — reference

Source: [Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)

Use in this plan: Measure only supported session capabilities; distance and direction are distinct.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S19

**WatchConnectivity** — reference

Source: [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)

Use in this plan: Reachability, state, queued transfers, and lifecycle reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S20

**RoomPlan** — reviewed

Source: [RoomPlan](https://developer.apple.com/augmented-reality/roomplan/)

Use in this plan: Semantic indoor room capture using camera and LiDAR.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S21

**Object Capture** — reviewed

Source: [Object Capture](https://developer.apple.com/documentation/realitykit/realitykit-object-capture/)

Use in this plan: Photogrammetry; capture and reconstruction are separate phases.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S22

**AR Quick Look** — reviewed

Source: [AR Quick Look](https://developer.apple.com/quick-look-gallery/)

Use in this plan: USDZ viewing, AR placement, and supported custom actions.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S23

**PHASE spatial audio** — reviewed

Source: [PHASE spatial audio](https://developer.apple.com/documentation/phase/phaseengine)

Use in this plan: Spatial sound engine and scene/audio lifecycle.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S24

**Personalized spatial audio** — reviewed

Source: [Personalized spatial audio](https://developer.apple.com/documentation/phase/personalizing-spatial-audio-in-your-app)

Use in this plan: Compatible headphones, optional profile entitlement, avoid double spatialization.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S25

**ShazamKit** — reviewed

Source: [ShazamKit](https://developer.apple.com/shazamkit/)

Use in this plan: Custom prerecorded-audio catalogs and second-screen matching.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S26

**ShazamKit session** — reviewed

Source: [ShazamKit session](https://developer.apple.com/documentation/shazamkit/shsession/)

Use in this plan: Custom-catalog matching does not require enabling the commercial Shazam catalog service.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S27

**tvOS Continuity Camera sample** — reviewed

Source: [tvOS Continuity Camera sample](https://developer.apple.com/documentation/avkit/supporting-continuity-camera-in-your-tvos-app)

Use in this plan: Sample requires Apple TV 4K second generation or later and physical devices.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S28

**Continued background processing** — reviewed

Source: [Continued background processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados/)

Use in this plan: User-initiated foreground work may continue; not an always-on daemon.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S29

**Accessibility audio graphs** — reviewed

Source: [Accessibility audio graphs](https://developer.apple.com/documentation/accessibility/audio-graphs)

Use in this plan: Chart semantics can expose audible data representations.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the macOS and iOS 27.0 SDKs): `AXChartDescriptor` and its axis, series, and point types, and SwiftUI's `accessibilityChartDescriptor(_:)`, with their declared availability, are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger). Access as a Superpower compiles them for macOS and iOS. The running Mac app exposes the descriptor as its chart's Audio Graph data, but nobody has played the Audio Graph on any device.

## S30

**Accessibility APIs** — reviewed

Source: [Accessibility APIs](https://developer.apple.com/documentation/accessibility/accessibility-api)

Use in this plan: Assistive technologies and accessibility metadata.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30): the custom actions, rotor, and input labels Access as a Superpower uses are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger). On the Mac they were read and performed through the accessibility API from another process, not by VoiceOver or Voice Control.

## S31

**AccessorySetupKit** — reviewed

Source: [AccessorySetupKit](https://developer.apple.com/documentation/AccessorySetupKit)

Use in this plan: Consent-oriented accessory discovery and configuration.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S32

**Accessory discovery** — reviewed

Source: [Accessory discovery](https://developer.apple.com/documentation/accessorysetupkit/discovering-and-configuring-accessories)

Use in this plan: Pairing configuration and Watch companion considerations.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S33

**AlarmKit** — reviewed

Source: [AlarmKit](https://developer.apple.com/documentation/alarmkit)

Use in this plan: App-owned alarms and authorization.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the iOS 27.0 SDK): `AlarmManager.shared`, `requestAuthorization()`, `authorizationState`, `schedule(id:configuration:)`, `cancel(id:)`, `AlarmConfiguration.alarm(schedule:attributes:)`, `Alarm.Schedule.fixed(Date)`, `AlarmAttributes`, `AlarmMetadata`, and `AlarmPresentation.Alert` (title-only from iOS 26.1; `stopButton` deprecated) are in the installed `AlarmKit.swiftinterface`, declared iOS 26.0 and unavailable on Mac Catalyst. There is no AlarmKit framework in the macOS SDK. Findings are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger). Compiled into `LabPhoneSurfaces` only; not run on a device.

## S34

**CarPlay entitlements** — reviewed

Source: [CarPlay entitlements](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)

Use in this plan: Category-specific managed capability; approval is not automatic.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S35

**Push to Talk** — reviewed

Source: [Push to Talk](https://developer.apple.com/documentation/pushtotalk/creating-a-push-to-talk-app/)

Use in this plan: System PTT lifecycle plus app-owned audio transport and APNs.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S36

**Family Controls configuration** — reference

Source: [Family Controls configuration](https://developer.apple.com/documentation/xcode/configuring-family-controls)

Use in this plan: Development and distribution permissions are distinct.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S37

**Developer account capabilities** — reviewed

Source: [Developer account capabilities](https://developer.apple.com/help/account/basics/about-your-developer-account)

Use in this plan: Personal development and distribution capabilities differ.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S38

**SwiftUI, WWDC26** — reviewed

Source: [SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)

Use in this plan: Native scene, document, and material evolution.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the macOS 27.0 SDK): `MenuBarExtra` and `WindowGroup(id:for:content:)` availability are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#desktop-scenes-and-services-lab-042). Desktop Native Power compiles them into the Mac host. No menu, document window, or menu-bar item was used from a running app, and none of this ran on a device.

## S39

**MIT license reference** — reviewed

Source: [MIT license reference](https://opensource.org/license/mit)

Use in this plan: Canonical license reference for release preparation.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S40

**ARKit** — reference

Source: [ARKit](https://developer.apple.com/documentation/arkit)

Use in this plan: Platform-specific AR configurations and runtime support checks.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the macOS and iOS 27.0 SDKs): the RealityKit and ARKit symbols Tabletop Reality uses, with their declared availability, are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#realitykit-and-arkit-lab-023). The virtual table was drawn and driven in the iOS 27.0 simulator; the ARKit adapter was compiled for the iOS device and simulator and has not run.

## S41

**AVFoundation** — reference

Source: [AVFoundation](https://developer.apple.com/documentation/avfoundation)

Use in this plan: Playback, capture, export, and timing reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the macOS and iOS 27.0 SDKs): the AVAudioEngine, Audio Unit, and realtime-annotation symbols Audio Workshop uses, with their declared availability, are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#audio-graph-audio-unit-and-midi-lab-029). They ran on the Mac in offline manual rendering, which opens no audio device, and compiled for the iOS simulator. Nothing played through a speaker.

## S42

**ScreenCaptureKit** — reference

Source: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)

Use in this plan: User-authorized Mac capture reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S43

**HealthKit** — reference

Source: [HealthKit](https://developer.apple.com/documentation/healthkit)

Use in this plan: Health permissions and workout session reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S44

**HomeKit** — reference

Source: [HomeKit](https://developer.apple.com/documentation/homekit)

Use in this plan: Home database access reference; not universal vendor control.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the iOS 27.0 and macOS 27.0 SDKs, LAB-037-A): HomeKit is present on iOS and `API_UNAVAILABLE(macos)` (no `HomeKit.framework` in the macOS SDK). `HMHomeManager.authorizationStatus`, `HMAccessory.isReachable`, `HMServiceTypeLightbulb` / `LockMechanism` / `Door` / `SecuritySystem` / `Thermostat`, and `HMCharacteristicTypePowerState` / `Brightness` are recorded in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#homekit-lab-037). CoreLocal does not link HomeKit or declare `com.apple.developer.homekit`; the fictional home is the shipped path. No live HomeKit run.

## S45

**Wallet passes** — reference

Source: [Wallet passes](https://developer.apple.com/documentation/walletpasses)

Use in this plan: Pass signing and updates reference; secure-element features separate.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the iOS 27.0 SDK): `PKPass`, `PKPassLibrary`, `PKAddPassesViewController`, and `PKPassTypeBarcode` are in the installed PassKit headers, with their declared availability recorded in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#wallet-passes-lab-038). LAB-038-A does not link PassKit into CoreLocal; it ships the unsigned preview and sample event card. No Wallet install or device add-passes run.

## S46

**StoreKit** — reference

Source: [StoreKit](https://developer.apple.com/documentation/storekit)

Use in this plan: Local testing and transaction verification reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S47

**AuthenticationServices** — reference

Source: [AuthenticationServices](https://developer.apple.com/documentation/authenticationservices)

Use in this plan: Passkeys and authentication reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK (LAB-041-A, Xcode 27.0 / 27A266a, macOS 27.0 and iOS 27.0, headers also present on watchOS and tvOS): `ASAuthorizationPlatformPublicKeyCredentialProvider` `initWithRelyingPartyIdentifier:`, `createCredentialRegistrationRequestWithChallenge:name:userID:`, and `createCredentialAssertionRequestWithChallenge:` are macOS 12.0, iOS 15.0, tvOS 16.0, and `API_UNAVAILABLE` on watchOS. `ASPublicKeyCredential` exposes `credentialID` and `rawClientDataJSON`, plus `rawAttestationObject` on a registration; it does not expose a private key. This build links the symbol and does not present a controller. `LAContext` and `SecItem` facts are in the installed SDK ledger.

## S48

**Translation** — reference

Source: [Translation](https://developer.apple.com/documentation/translation)

Use in this plan: Language availability and translation-session reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S49

**Game Controller** — reference

Source: [Game Controller](https://developer.apple.com/documentation/gamecontroller)

Use in this plan: Controller capability and input reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 (27A266a), from `GCController.h` and `GCDeviceHaptics.h` in the iOS 27.0 SDK, for LAB-030-A): `GCController.haptics` is a nullable `GCDeviceHaptics`, available on macOS 11.0, iOS 14.0, and tvOS 14.0. `createEngineWithLocality:` is the same availability; Swift name `createEngine(withLocality:)`. `GCHapticsLocalityDefault` is guaranteed. The watchOS SDK has no GameController framework. No entitlement. On the research Mac the probe found no controller reporting haptics. No controller was played.

## S50

**Core Haptics** — reference

Source: [Core Haptics](https://developer.apple.com/documentation/corehaptics)

Use in this plan: Hardware-sensitive haptic/audio pattern reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 (27A266a), from the Core Haptics headers in the iOS, macOS, and tvOS 27.0 SDKs, for LAB-030-A): `CHHapticEngine` is iOS 13.0, macOS 10.15, tvOS 14.0, and unavailable on watchOS. The watchOS SDK has no Core Haptics framework. `capabilitiesForHardware()` returns `supportsHaptics` and `supportsAudio`. `makePlayer(with:)` is the Swift name of `createPlayerWithPattern:error:`. `CHHapticTimeImmediate` is 0. No entitlement. On the research Mac, `supportsHaptics` was false. No pattern was played.

## S51

**GameKit** — reference

Source: [GameKit](https://developer.apple.com/documentation/gamekit)

Use in this plan: Game Center identity and multiplayer reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S52

**App Clips** — reference

Source: [App Clips](https://developer.apple.com/app-clips/)

Use in this plan: Small install/invocation experience reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S53

**PencilKit** — reference

Source: [PencilKit](https://developer.apple.com/documentation/pencilkit)

Use in this plan: Drawing and input reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S54

**Metal** — reference

Source: [Metal](https://developer.apple.com/metal/)

Use in this plan: GPU feature-family and rendering reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S55

**Vision** — reference

Source: [Vision](https://developer.apple.com/documentation/vision)

Use in this plan: Image-analysis request reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0, from the macOS 27.0 SDK's `Vision.swiftinterface`, for LAB-012-A). No entitlement is required to recognize text or barcodes in image bytes a person chose. The camera is not used.

| Symbol LAB-012 uses | Installed signature | Declared availability |
|---|---|---|
| `RecognizeTextRequest` | `ImageProcessingRequest` whose `Result` is `[RecognizedTextObservation]`. `perform(on:)` takes the image `Data`. | macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0 |
| `RecognizedTextObservation.transcript` | `String` | macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0 |
| `DetectBarcodesRequest` | `ImageProcessingRequest` whose `Result` is `[BarcodeObservation]` | macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 27.0 |
| `BarcodeObservation.payloadString` | `String?` | Same as `BarcodeObservation`: macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 27.0 |

Watch and Apple TV hosts do not link the module. A drawn image and a generated QR code were read in `VisionAdapterTests` on the development Mac. That is not a camera and not a device photograph.

## S56

**Core MIDI** — reference

Source: [Core MIDI](https://developer.apple.com/documentation/coremidi)

Use in this plan: MIDI transport and endpoint reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30): the Core MIDI input symbols Audio Workshop uses are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#audio-graph-audio-unit-and-midi-lab-029). They compile for macOS and iOS; no MIDI client has been created in a test or with a real source.

## S57

**AppKit** — reference

Source: [AppKit](https://developer.apple.com/documentation/appkit)

Use in this plan: Desktop document, services, and scripting reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the macOS 27.0 SDK): `NSApplication.servicesProvider` is in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#desktop-scenes-and-services-lab-042). The Services item is an Info.plist declaration. The system Services menu was not invoked, and this did not run on a device.

## S58

**ActivityKit** — reference

Source: [ActivityKit](https://developer.apple.com/documentation/activitykit)

Use in this plan: Live Activity lifecycle reference; extension surface is not unlimited execution.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S59

**WidgetKit** — reference

Source: [WidgetKit](https://developer.apple.com/documentation/widgetkit)

Use in this plan: Widget and Control configuration reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 with the iOS 27.0 SDK): the widget, Control, reload, and privacy symbols Surface Deck uses, with their declared availability, are in the [installed SDK ledger](VERIFICATION_BOUNDARIES.md#widgets-controls-and-where-their-intents-run-lab-004). They were compiled for iOS and run in the iOS 27.0 simulator, not on a device: the App Group they need cannot be signed by a free Personal Team.

## S60

**NSUserActivity** — reference

Source: [NSUserActivity](https://developer.apple.com/documentation/foundation/nsuseractivity)

Use in this plan: Handoff/continuation metadata reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0, the macOS, iOS, watchOS, and tvOS 27.0 SDKs): `NSUserActivity` is in `Foundation.framework/Headers/NSUserActivity.h`, not the Foundation Swift interface. The class is `API_AVAILABLE(macos(10.10), ios(8.0), watchos(2.0), tvos(9.0))`. `isEligibleForHandoff`, `requiredUserInfoKeys`, `becomeCurrent`, and `resignCurrent` are available on macOS 10.11, iOS 9, watchOS 3, and tvOS 10. `userInfo` values are property-list types. The header says continuation requires the same developer Team ID and the activity type listed under `NSUserActivityTypes`. SwiftUI `userActivity(_:isActive:_:)` and `onContinueUserActivity(_:perform:)` are iOS 14, macOS 11, tvOS 14, and watchOS 7. No entitlement. LAB-016-A does not set `webpageURL` or `supportsContinuationStreams`. Two-device delivery was not run.

## S61

**Network framework** — reference

Source: [Network framework](https://developer.apple.com/documentation/network)

Use in this plan: Local networking transport reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S62

**Visual Intelligence integration** — reference

Source: [Visual Intelligence integration](https://developer.apple.com/documentation/appintents/visual-intelligence)

Use in this plan: App participation requires supported system queries; not arbitrary camera interception.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0, from the macOS 27.0 SDK, for LAB-012-A). No entitlement is declared for this participation. The intent reads labels only.

| Symbol LAB-012 uses | Installed signature | Declared availability |
|---|---|---|
| `SemanticContentDescriptor` | `labels: [String]` and a pixel buffer. The intent does not read the buffer. | iOS 26.0, macOS 27.0, Mac Catalyst 27.0 |
| `AppSchema.visualIntelligence.semanticContentSearch` | Resolves to the intent name `ShowVisualSearchResultsInAppIntent` | iOS 26.0, macOS 27.0; unavailable on tvOS, watchOS, and visionOS |
| `Attachment` from a `CGImage` | `Attachment<Content>` and `ImageAttachment.init(_ cgImage: CGImage, orientation:)` in Foundation Models ([S06](#s06)) | iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0; unavailable on tvOS |

The visual-search intent is compiled only for a 6.4 compiler, on iOS and macOS. A 26-family build does not include it. It has not been invoked by the system.

## S63

**Core ML** — reference

Source: [Core ML](https://developer.apple.com/documentation/coreml)

Use in this plan: Runtime model execution reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30, Xcode 27.0 (27A266a), from the macOS 27.0 SDK's `CoreML.swiftinterface`, for LAB-015-A). Availability is the SDK's declaration. LAB-015 does not call these symbols and does not link Core ML. The fixture executor is the path that runs.

| Symbol read, not called | Installed signature | Declared availability |
|---|---|---|
| `MLModel.load` | `class func load(contentsOf url: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> MLModel` | macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0 |
| `MLComputePlan.load` | `static func load(contentsOf url: URL, configuration: MLModelConfiguration) async throws -> MLComputePlan` and the `MLModelAsset` overload | macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4 |
| `MLComputePlan.estimatedCost` | `func estimatedCost(of operation: MLModelStructure.Program.Operation) -> MLComputePlan.Cost?`, where `Cost` is `let weight: Double` | same as `MLComputePlan` |

No symbol in that interface reports a byte size before `load`. Foundation Models, read for the same ticket, has no evaluation harness; `DynamicProfileBuilder` uses "evaluate" only as a compiler diagnostic. The bench does not import that framework.

## S64

**Siri AI availability** — reviewed

Source: [Siri AI availability](https://support.apple.com/en-gw/127893)

Use in this plan: Siri AI is beta; eligibility and rollout are independent of compiling an intent.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-30): LAB-002 declares no App Shortcut and does not call Siri. The decision card is the same when Siri is treated as disabled. Siri rollout stays a separate gate ([installed SDK ledger](VERIFICATION_BOUNDARIES.md#installed-sdk-ledger)).
