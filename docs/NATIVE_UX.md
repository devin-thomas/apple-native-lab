# Native interaction and design

## Shared visual language

Use system typography, semantic foreground/background roles, system-adaptive Light/Dark appearance, clear hierarchy, and restrained motion. Native materials and Liquid Glass belong primarily to controls/navigation, not every content card. Avoid a translucent surface behind dense text unless contrast remains reliable at every scroll position. The default demo uses original abstract color/geometry, not downloaded scenery or copied product art. [S38](SOURCE_INDEX.md#s38).

Every experiment has five recognizable areas: the payoff, current capability state, primary action, visible result, and a compact “How this works” inspector. The inspector explains the actual route—local model, manual entry, fixture, LAN, queued Watch transfer—not an aspirational route.

## Device-specific rules

Mac: use a main WindowGroup, native sidebar/detail hierarchy, keyboard shortcuts, commands, context menus, Settings, and focused auxiliary windows where warranted. A MenuBarExtra is supplemental, not a replacement for discoverable controls. Persist window/scene state without unexpectedly revealing sensitive documents on relaunch. Prefer SwiftUI and use AppKit narrowly for a capability SwiftUI does not supply.

iPhone: prioritize reachable primary actions, clear permission staging, document pickers, native sharing, and resizable content at accessibility text sizes. Do not imitate an old fixed-size screen. iPad may use split layouts, multiwindow, drag/drop, and optional ink, but its absence must not block the baseline.

Watch: display one meaningful action or status at a time. Distinguish pending from acknowledged. Haptic feedback must not pretend a remote action is applied when it is only queued. No assumed physical Action button. Complications and notifications redact sensitive labels.

TV: design for focus navigation and large readable content. Offer a disconnected/stale state, not a frozen screen masquerading as live. A remote or controller must retain a usable escape path. Phone-as-camera and phone-as-controller roles need explicit coordination rather than assuming all camera/AR sessions coexist.

## Accessibility rules

Every essential function has a labeled semantic control and a non-gesture-only path. Charts expose textual summaries and structured data; add audio graph semantics where supported. [S29](SOURCE_INDEX.md#s29), [S30](SOURCE_INDEX.md#s30).

Test VoiceOver traversal, keyboard focus, Dynamic Type where applicable, increased contrast, reduced motion, reduced transparency, color-independent state, and captions/transcripts for meaningful audio. Haptics and sound enhance state but do not become its only representation. Use original chart fixtures whose textual and audible interpretation can be checked exactly.

## Honest states

Use explicit copy for `Unverified on this device`, `Needs permission`, `Needs model assets`, `Requires additional setup`, `Unavailable here`, `Using a fixture`, and `Ready`. Never show a green “Supported” badge merely because the device model is new. A technical failure should explain the smallest actionable next step without demanding unrelated permissions.
