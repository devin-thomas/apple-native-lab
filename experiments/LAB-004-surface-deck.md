---
id: "LAB-004"
title: "Surface Deck"
state: "implemented"
milestone: "M1"
category: "System surfaces"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-004 — Surface Deck

## The moment

One reversible session state appears in a widget, a Control, and the main app.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; supported Watch surfaces.

**Primary APIs:** WidgetKit, Control widgets, AppIntents. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** SessionSnapshot, ControlState. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Build small/medium widgets from immutable snapshots
2. Expose one toggle and one launch action
3. Let users add Controls and map supported hardware triggers
4. Refresh by documented policy rather than a live polling timer

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Stale widget toggles reconcile to current state.
- [ ] Locked-device view redacts private labels.
- [ ] A denied update budget leaves a correct stale indicator.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Widget/Control availability is per platform. An iPhone Action button does not imply a Watch Action button.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Main-app state deck and static widget previews.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/surface-deck/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-004-A):

- `Packages/LabDomain`: the session itself. `LabSession` is a running-or-paused flag with a revision, always in the demo namespace, and `DomainOperation.setSession(id:expected:running:)` starts or pauses it. The operation is not destructive, and its receipt's undo is the opposite change. A stale expected revision gets a conflict receipt, as every operation does. Reset Demo pauses a running session at its next revision and never removes it.
- `Packages/LabStore`: schema version 3 adds a `sessions` table whose rows can only be in the demo namespace.
- `Packages/LabFeatures/Sources/SurfaceDeck/`: `SessionActions`, which the deck and the intents share; the App Intents `SetDemoSessionIntent` (the toggle), `GetDemoSessionIntent`, and `OpenSurfaceDeckIntent` (the launch action); the immutable `SessionSnapshot` and its file; `SurfacePresentation`, which decides what a surface shows for a snapshot, a stale one, or none; and the SwiftUI widget views. It depends on LabDomain only. It imports SwiftUI and AppIntents, never WidgetKit, the store, or a model.
- `Extensions/SurfaceWidgets/` (SystemSurfaces): the widget (small, medium, and Lock Screen rectangular), the Demo Session Control toggle, and the Open Surface Deck Control. It reads the snapshot file and nothing else. `LabPhoneSurfaces` embeds it; `LabPhone` does not.
- `Apps/Shared/SurfaceDeck/`: the host's model, its backend over `LabLibrary` and `LabDataService`, the snapshot publisher, and the deck. iPhone and iPad reach the deck from this experiment's catalog page, and the launch action presents it. The Mac has a Surface Deck sidebar destination and View › Surface Deck (⌘7).

## Implementation notes (LAB-004-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs, on the Mac and in an iOS 27.0 simulator. These are compile and simulator facts, not device proof.

- The session state is a demo "session: running or paused" flag. It is small, holds nothing a person wrote, and every change has an exact inverse, so a Control can change it without a confirmation dialog: it needs no ADR-013 grant. A share extension or a peer still could not change it without one, and a model tool can only propose it (ADR-011).
- Where an intent runs decided the design. From a widget toggle, a plain `SetValueIntent` performed in the widget extension, which has no store, so it refused. As a `LiveActivityIntent` it performed in the app's process. When the app was not running, the system launched it in the background (`runningBackgroundSuspended`), and the change committed through `OperationService` as an App Intent with a receipt. The conformance is iOS only and is used for that routing alone; no Live Activity starts. The Control toggle took the same path.
- The launch action is an `OpenIntent` with a one-case destination and `supportedModes = .foreground(.immediate)`. From Control Center it brought the app forward with the deck showing, from a terminated app and from one in the background. An earlier plain `AppIntent` version ran `perform()` in the app, but those runs crashed on the problem in the next note, so whether it would have come forward was not judged.
- The widget's `Toggle(isOn:intent:)` did not set a `SetValueIntent`'s `value` (the system logged `Prepared value to Bool(nil)` and asked for one). So each surface builds the intent with the value it offers, the opposite of what it shows, and the revision it shows.
- A deck presented as a sheet from the iPhone root, when the launch action brings the app forward, has the library passed into the sheet explicitly. Launches crashed on a missing environment object before that change; after it, 6 launches from a clean install passed.
- The snapshot is a few hundred bytes of JSON: state, revision, write time, and, only when the person turns on Show Details on Widgets, where and when it last changed. It is written with `completeFileProtectionUntilFirstUserAuthentication`, so the Lock Screen widget can read it after first unlock. A link, a non-file, a file over 2 KB, malformed JSON, another format, or a newer version reads as unusable.
- Refresh: the app asks WidgetKit to reload only when the snapshot would look different, or when a surface acted on a stale or missing state. Each timeline has the snapshot now and the same snapshot marked "May be out of date" an hour later, with one refresh requested then. There is no timer. A Control keeps its last value until it is reloaded, so it has no stale mark.
- WidgetKit cached timelines: after the snapshot file was deleted, an existing widget and a newly added one kept the cached state until the app was reinstalled, which reloaded them to the placeholder.
- The Mac has no widget or Control extension. A Mac widget would need its own SystemSurfaces host variant and App Group, which CoreLocal cannot carry, so the Mac shows the deck and its previews only.

## Delivery

[Implementation ticket](../tickets/LAB-004-A.md) → [qualification ticket](../tickets/LAB-004-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S01](../docs/SOURCE_INDEX.md#s01), [S59](../docs/SOURCE_INDEX.md#s59). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
