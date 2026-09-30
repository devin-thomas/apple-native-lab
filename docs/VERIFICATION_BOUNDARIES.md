# What has—and has not—been verified

Research snapshot: 2026-09-29. This pack is design work, not an Xcode/device test report.

The [source index](SOURCE_INDEX.md) distinguishes **reviewed** primary-source content from **reference** links queued for implementation research. A reviewed source supports the stated API direction only. When the pack was written, no SDK symbol in it had been compiled and no physical-device test had been performed. Symbols compiled since then are listed in the [installed SDK ledger](#installed-sdk-ledger) below, with what was and was not demonstrated.

## Important precision boundaries

| Tempting assumption | Specification boundary |
|---|---|
| Every new Apple device can run the same intelligence model | Probe per-device model availability. Watch/TV are not presumed local Foundation Models hosts. |
| PCC is a free general API for every developer or source install | Qualifying program, account entitlement, user availability, and permitted distribution are separate gates. [S07](SOURCE_INDEX.md#s07) |
| Ten App Shortcuts means only ten possible actions | Curated App Shortcuts and the larger App Intent action library are different products. Follow platform-specific HIG support. [S03](SOURCE_INDEX.md#s03) |
| Siri understands every arbitrary noun/action | Adopt only matching documented schemas; availability/rollout is a separate gate. In-app intent flows remain complete. [S02](SOURCE_INDEX.md#s02), [S64](SOURCE_INDEX.md#s64) |
| A Live Activity keeps any computation alive | It is a presentation surface. Work has its own permitted lifetime, checkpoint, and expiration handling. [S28](SOURCE_INDEX.md#s28), [S58](SOURCE_INDEX.md#s58) |
| CloudKit or Handoff is instant live synchronization | Durable sync, live transport, and continuation have separate contracts. [S15](SOURCE_INDEX.md#s15), [S60](SOURCE_INDEX.md#s60) |
| Wi-Fi Aware creates a universal Mac/Watch/TV mesh | Use actual runtime capabilities and separately qualify each platform. LAN is the default multi-platform transport. [S17](SOURCE_INDEX.md#s17) |
| A Watch provides unrestricted continuous motion/streaming | Normal lifecycle rules still apply; do not create fake workouts. [S19](SOURCE_INDEX.md#s19), [S43](SOURCE_INDEX.md#s43) |
| A generic Bluetooth/Wi-Fi board can do every accessory feature | ASK, BLE, UWB, Wi-Fi Aware, and vendor protocols are distinct capabilities. [S31](SOURCE_INDEX.md#s31), [S32](SOURCE_INDEX.md#s32) |
| The Apple TV model can be inferred from an informal generation description | Record the actual model; Continuity Camera's sample has a second-generation-or-later Apple TV 4K gate. [S27](SOURCE_INDEX.md#s27) |
| A shaped model response is factually correct | Guided generation constrains structure. Validation, evidence, and review remain necessary. [S06](SOURCE_INDEX.md#s06) |
| Source compilation means users can install an unsigned app anywhere | Supported device installation, signing, and distribution are separate. [S37](SOURCE_INDEX.md#s37) |

## 27-generation features

Foundation Models' 2026 material covers image inputs, a provider abstraction, richer session behavior, and evaluation tooling; those directions belong in isolated 27-generation experiments, not assumptions about every older deployment target. [S06](SOURCE_INDEX.md#s06).

Shortcuts Storage and newer system intent testing likewise have their own availability and setup. A future builder must check the concrete installed API, test actual cross-device IDs, and avoid shipping a guessed symbol based on a session transcript alone. [S04](SOURCE_INDEX.md#s04), [S05](SOURCE_INDEX.md#s05).

A background-inference entitlement or newly changed beta capability is not a baseline promise. Investigate it only in an isolated spike with current official evidence and account approval; ordinary foreground/local inference remains usable without that experiment.

## Source refresh rule

At the first implementation of a capability and before each release, record the official URL, review date, installed SDK symbol/signature, platform availability, required entitlements, demonstrated device, and remaining uncertainty. If documentation disagrees across locales or versions, retain the discrepancy and favor a minimal compile/device probe rather than guessing.

## Installed SDK ledger

Each row follows the source refresh rule above: the installed symbol and signature, its declared availability, entitlements, where it was demonstrated, and what remains uncertain. The evidence is the installed SDK itself: the `.swiftinterface` files of Xcode 27.0 (27A266a) with the macOS 27.0 and iOS 27.0 SDKs, read on 2026-09-29, and the builds and tests named in each row. A declared availability is the SDK's statement, not a run on that OS.

### App Intents (LAB-001)

Recorded at [LAB-001-B](../tickets/LAB-001-B.md) from the [LAB-001-A](../tickets/LAB-001-A.md) implementation. No entitlement is needed for any of these. None has run on a physical device, in Siri, or in the Mac Shortcuts app.

| Source | Installed symbol | Declared availability | Demonstrated | Remaining uncertainty |
|---|---|---|---|---|
| [S01](SOURCE_INDEX.md#s01) | `AppIntent.requestConfirmation(conditions:actionName:dialog:)`. The older `requestConfirmation(result:confirmationActionName:showPrompt:)` and `requestConfirmation(output:confirmationActionName:showPrompt:)` are marked deprecated in favor of it. | macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0 | Compiled into Archive Lab Item for macOS and iOS. In the iOS 27.0 simulator's Shortcuts app, it showed the intent's prompt with Archive and Cancel, Cancel changed nothing, and Archive committed (LAB-001-A). | The system dialog on a device, on the Mac, and through Siri |
| [S01](SOURCE_INDEX.md#s01) | `ConfirmationActionName.custom(acceptLabel:acceptAlternatives:denyLabel:denyAlternatives:destructive:)` | macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0 (the type's) | The Archive/Cancel labels in the same simulator run | How Siri speaks the labels and alternatives |
| [S01](SOURCE_INDEX.md#s01) | `IntentParameter.requestDisambiguation(among:dialog:)` | macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0 | Compiled into Create Lab Item. The chooser it feeds is tested with a stand-in in `ActionAtlasIntentTests` and `ActionAtlasQualificationTests`. | The system's disambiguation dialog was never shown |
| [S01](SOURCE_INDEX.md#s01) | `AppIntent.supportedModes: IntentModes`. `openAppWhenRun` is deprecated in macOS, iOS, watchOS, tvOS, and visionOS 26.0 with "Please provide 'supportedModes' instead". | `supportedModes` and `IntentModes`: every Apple OS 26.0 | The intents keep the default background mode | Foreground modes were not used |
| [S01](SOURCE_INDEX.md#s01) | `AppIntentsPackage` with `static var includedPackages` | macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0 | In Xcode 27.0, `appintentsmetadataprocessor` runs on a Swift package target, and the host's `Metadata.appintents` lists the package's 8 actions, 2 entities, 2 queries, and 1 enum once the host declares its own `AppIntentsPackage` that includes the package's. Conforming the `App` type itself does not compile under Swift 6. The hosted test `theBuiltAppCarriesTheActionAtlasIntentMetadata` checks the built Mac app. | Metadata from a 26-family SDK: no 26 SDK compile has run |
| [S03](SOURCE_INDEX.md#s03) | `AppShortcutsProvider` | macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0 | Not adopted: no curated App Shortcuts are declared, and the actions appear in Shortcuts as the atomic library | Curated App Shortcuts on each platform |
| [S05](SOURCE_INDEX.md#s05) | The `AppIntentsTesting` framework ships with Xcode 27.0 in each platform's `Developer/Library/Frameworks`, as test-only tooling. Its definitions are addressed by bundle identifier, such as `IntentDefinitions(bundleIdentifier:)`. | Every public type: macOS, iOS, watchOS, tvOS, and visionOS 27.0 | Not run | System-path tests need a signing team ([S05](SOURCE_INDEX.md#s05)) and a test target. The project's 26.0 floor also means such tests must be gated to 27.0. |
| [S02](SOURCE_INDEX.md#s02), [S64](SOURCE_INDEX.md#s64) | No App Schema is adopted | Not applicable | Siri was not used | Siri phrasing, schema matching, and availability |

### Widgets, Controls, and where their intents run (LAB-004)

Recorded at [LAB-004-B](../tickets/LAB-004-B.md) from the [LAB-004-A](../tickets/LAB-004-A.md) implementation. The symbols were read on 2026-09-30 from the iOS 27.0 SDK's `WidgetKit`, `SwiftUI`, `SwiftUICore`, `AppIntents`, and `_AppIntents_SwiftUI` interfaces in Xcode 27.0 (27A266a). The widget extension and the host that writes its snapshot carry an App Group entitlement, which a free Personal Team cannot sign, so none of this has run on a device. The simulator runs are the LAB-004-B records in [`evidence/LAB-004/`](../evidence/LAB-004/).

| Source | Installed symbol | Declared availability | Demonstrated | Remaining uncertainty |
|---|---|---|---|---|
| [S59](SOURCE_INDEX.md#s59) | `StaticConfiguration` with `supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])`, a `TimelineProvider` returning `Timeline(entries:policy: .after(_:))`, and `containerBackground(_:for: .widget)` | `systemSmall` and `systemMedium`: iOS 14.0, macOS 11.0, unavailable on watchOS and tvOS. `accessoryRectangular`: iOS 16.0, watchOS 9.0, visionOS 27.0, unavailable on macOS and tvOS | The small widget on the Home Screen of an iOS 27.0 simulator, from three clean installs: the placeholder before the app first ran, then the state, and redrawn after each change | The medium and Lock Screen widgets on the system: LAB-004-A added them in the simulator, and LAB-004-B checked only the small one. A refresh the system declines, and a Lock Screen widget on a locked device |
| [S59](SOURCE_INDEX.md#s59) | `ControlWidget` (SwiftUI), `StaticControlConfiguration`, `ControlValueProvider`, `ControlWidgetToggle(isOn:action:label:valueLabel:)`, whose action must be a `SetValueIntent` with a `Bool` value, and `ControlWidgetButton(action:label:)`, which has its own overload for an `OpenIntent` | iOS 18.0, macOS 26.0, watchOS 26.0; unavailable on tvOS and visionOS | Both Controls added from the Control Center gallery and used in the simulator. The toggle's value returned to the current state about 5 seconds after a refused tap | A Control on the Mac or the Watch: none is built. The Action button and the Lock Screen |
| [S59](SOURCE_INDEX.md#s59) | `WidgetCenter.reloadTimelines(ofKind:)` and `ControlCenter.reloadControls(ofKind:)` | `WidgetCenter`: iOS 14.0, macOS 11.0, watchOS 9.0. `ControlCenter`: iOS 18.0, macOS 26.0, watchOS 26.0 | Called only after the snapshot changes or a surface acted on a stale state; the widget and the Control redrew within seconds in the simulator | How a device's reload budget treats these calls |
| [S01](SOURCE_INDEX.md#s01) | `SetValueIntent` | macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0 | The toggle's intent. The widget's `Toggle(isOn:intent:)` left its `value` unset in the simulator (LAB-004-A), so each surface builds the intent with the value it offers | Whether a later OS sets `value` from the toggle |
| [S01](SOURCE_INDEX.md#s01) | `LiveActivityIntent` | iOS 17.0; unavailable on macOS, watchOS, and tvOS | The toggle's intent conforms on iOS only so that `perform()` runs in the app's process. From the widget and the Control, with the app terminated, the system launched the app in the background, and every tap committed or conflicted there with an App Intent receipt. No Live Activity starts | Whether this routing is the documented behavior for a widget or Control intent, rather than an observed one; how it behaves on a device |
| [S01](SOURCE_INDEX.md#s01) | `OpenIntent` with `supportedModes = .foreground(.immediate)`; `IntentModes` | `OpenIntent`: macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0. `IntentModes`: every Apple OS 26.0 | The Open Surface Deck Control brought the app forward with the deck 9 times from clean installs, 3 of them before the app had ever run, with no crash | A device, the Action button, and Shortcuts |
| [S59](SOURCE_INDEX.md#s59) | `Toggle(isOn:intent:label:)` in `_AppIntents_SwiftUI`, which the widget extension links | iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0 | The widget's toggle in the simulator. The release manifest records the link (LAB-004-A) | None beyond the widget's own |
| [S59](SOURCE_INDEX.md#s59) | `View.privacySensitive(_:)` and `RedactionReasons.privacy` | iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0 | Drawn with the privacy redaction in a package test and read back by text recognition: the detail line is gone and the state stays readable. The deck's "Lock Screen, locked" preview uses the same redaction | That the system applies it to this widget on a locked device |

