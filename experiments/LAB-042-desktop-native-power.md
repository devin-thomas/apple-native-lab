---
id: "LAB-042"
title: "Desktop Native Power"
state: "implemented"
milestone: "M2"
category: "Mac"
depends_on: ["LAB-001", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-042 — Desktop Native Power

## The moment

Use a command palette, menu-bar status, multiwindow documents, and one deliberate automation entry point.

## Scope and native leverage

**Hosts:** Mac only.

**Primary APIs:** SwiftUI scenes, AppKit, Services, optional scripting. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** DesktopCommand, WindowRoute. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use native window/menu/keyboard conventions
2. Add a Services-style selected-text import
3. Expose an allowlisted scriptable operation if appropriate
4. Restore scene state without reopening private content unexpectedly

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Every gesture-only action has a discoverable alternate path.
- [ ] Closing a window does not destroy its document.
- [ ] No arbitrary shell text is executed from an intent.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Desktop scripting is a separate permission boundary, not a cross-platform universal ability.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Standard menu command and file import.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

- `Packages/LabFeatures/Sources/DesktopNativePower/`: `DesktopCommand`, `DesktopDocument`, `WindowRoute` as `DesktopWindow` plus `SceneSnapshot`, the note parser, `ScriptAdmission`, `DesktopStation`, and `RunDesktopCommandIntent`. It depends on LabDomain and commits through a `DesktopBackend`. It never holds the store. The bundled fixture is `sample-desk-note.txt`.
- `Apps/Mac/Desktop/`: the session, the list and detail, the document window, the menu-bar menu, and the Services provider. The Mac host links the product. iPhone, Watch, and Apple TV do not.

## Implementation notes (LAB-042-A)

Observed with Xcode 27.0 and the macOS 27.0 SDK, read on research. These are package-test facts on that Mac, not a running menu, a Services menu invocation, or a device.

- `MenuBarExtra` is macOS 13.0 and unavailable on iOS, watchOS, tvOS, and visionOS. `WindowGroup(id:for:content:)` is iOS 16.0 and macOS 13.0, unavailable on watchOS and tvOS. Both are below the 26.0 floor, so neither is gated. `NSApplication.servicesProvider` is the AppKit `NSServicesHandling` property, with no availability macro on that declaration. No new entitlement: the file dialog uses the user-selected file access LabMac already has, and the Services item is an Info.plist declaration. The symbols are in the [installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md#desktop-scenes-and-services-lab-042).
- A note import commits `createItem` in the user collection Desktop Notes through `OperationService`. The menu uses the app UI actor. The intent uses the App Intent actor. A model tool is refused and writes nothing.
- `RunDesktopCommandIntent` takes an enum, `import-fixture-note` or `show-status`. `ScriptAdmission` refuses any other string, including shell text, before a commit. Importing selected text that happens to look like a shell stores it as a note and does not run it.
- Closing a window removes the window. The document and its lab item stay. A private note can be open in the session that imported it. Its id is left out of the scene storage key, and a restored snapshot that names it does not open it.
- Reset Fixture Notes removes the uncommitted fixture preview only.

## Qualification notes (LAB-042-B)

The experiment stays `implemented`. [Qualification](../tickets/LAB-042-B.md), [evidence](../evidence/LAB-042/), and the [walkthrough](../docs/walkthroughs/LAB-042-desktop-native-power.md) distinguish package and Mac hosted adapter fixtures from system interaction. No physical mobile device or manual assistive-technology pass is claimed.

Stable import identity includes text, origin, and privacy. Menu and intent fixture imports share the script origin; a file import of those bytes is a separate item. Private notes are not encrypted and their titles remain listed; the boundary is automatic body presentation and scene restoration.

Current source limitations: native document close is not forwarded to the station, repeated ordinary restore adds routes, the menu-bar Open command does not select the desktop destination, and file-picker cancellation reports invalid text. The Services error pointer covers immediate admission only; later asynchronous import failures remain in the session. These require live qualification or follow-up rather than a state promotion.

## Delivery

[Implementation ticket](../tickets/LAB-042-A.md) → [qualification ticket](../tickets/LAB-042-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S57](../docs/SOURCE_INDEX.md#s57), [S38](../docs/SOURCE_INDEX.md#s38). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
