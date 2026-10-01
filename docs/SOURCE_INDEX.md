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

Source: [Private Cloud Compute eligibility](https://developer.apple.com/private-cloud-compute/)

Use in this plan: Small Business Program, download threshold, entitlement, and permitted distribution gates.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

Installed SDK check (2026-09-29): the 27.0 SDKs declare `PrivateCloudComputeLanguageModel` for iOS, macOS, visionOS, and watchOS 27.0, with `availability`, `quotaUsage`, and network, quota, and service errors. No lab code references it; a LAB-010 test fails if Typed Local Intelligence ever does. The route remains `blocked` until each gate above is shown.

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

## S41

**AVFoundation** — reference

Source: [AVFoundation](https://developer.apple.com/documentation/avfoundation)

Use in this plan: Playback, capture, export, and timing reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

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

## S45

**Wallet passes** — reference

Source: [Wallet passes](https://developer.apple.com/documentation/walletpasses)

Use in this plan: Pass signing and updates reference; secure-element features separate.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

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

## S50

**Core Haptics** — reference

Source: [Core Haptics](https://developer.apple.com/documentation/corehaptics)

Use in this plan: Hardware-sensitive haptic/audio pattern reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

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

## S56

**Core MIDI** — reference

Source: [Core MIDI](https://developer.apple.com/documentation/coremidi)

Use in this plan: MIDI transport and endpoint reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S57

**AppKit** — reference

Source: [AppKit](https://developer.apple.com/documentation/appkit)

Use in this plan: Desktop document, services, and scripting reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

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

## S63

**Core ML** — reference

Source: [Core ML](https://developer.apple.com/documentation/coreml)

Use in this plan: Runtime model execution reference.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.

## S64

**Siri AI availability** — reviewed

Source: [Siri AI availability](https://support.apple.com/en-gw/127893)

Use in this plan: Siri AI is beta; eligibility and rollout are independent of compiling an intent.

Implementation evidence required: actual SDK symbol/availability, permissions or entitlement, and a named compile/device result.
