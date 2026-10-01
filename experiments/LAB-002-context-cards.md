---
id: "LAB-002"
title: "Context Cards"
state: "implemented"
milestone: "M2"
category: "System surfaces"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-002 — Context Cards

## The moment

Ask about the visible object, then complete a small decision inside a system presentation.

## Scope and native leverage

**Hosts:** iPhone and iPad; Mac support probed separately.

**Primary APIs:** App Schemas, NSUserActivity, SwiftUI snippets. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** VisibleEntityContext, DecisionProposal. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Associate one primary sample entity with its view
2. Map only genuinely matching Apple schemas
3. Render an interactive confirmation where supported
4. Resolve stale visible content without touching a different object

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A replaced onscreen item cannot mutate the previous item.
- [ ] A schema mismatch fails the integration gate.
- [ ] Siri-disabled devices retain the same decision UI.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No invented universal schema for arbitrary business nouns; Siri rollout and region are separate gates.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

In-app card and typed Shortcut remain complete; context resolution is explicitly unavailable.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/context-cards/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-002-A):

- `Packages/LabFeatures/Sources/ContextCards/`: `VisibleEntityContext`, `DecisionProposal`, `DecisionCard`, and `ContextBoard`; `SchemaGate`, which refuses every claim for a lab sample; `ContextCardsActions.setAside`, which archives through Action Atlas after the screen check; `AskAboutVisibleSampleIntent` and `SetAsideSampleIntent`; the snippet and `View.visibleSample`. It depends on ActionAtlas and LabDomain and never holds the store. No new `DomainOperation`.
- `Apps/Shared/ContextCards/`: the session, the card, and `ContextCardsHost.connect`, which wraps the same library Action Atlas uses. The Mac reaches it from the sidebar and View › Context Cards (⌘9), with its columns in `Apps/Mac/Window/ContextCardsColumns.swift`. The iPhone reaches it from this experiment's catalog page (Open Context Cards), with no new tab.

## Implementation notes (LAB-002-A)

Observed with Xcode 27.0 and the iOS 27.0 and macOS 27.0 SDKs. These are Mac and simulator-compile facts, not device proof, and not a run of Siri or the Shortcuts app.

- No Apple schema is adopted. The iOS 27.0 SDK's `AppSchema` domains are audio, books, browser, calendar, clock, files, journal, mail, maps, messages, notes, phone, photos, presentation, reader, reminders, spreadsheet, whiteboard, and wordProcessor. A lab sample is none of them. `SchemaGate` refuses a claim for any of those domains, and a domain that is not in the list. A refused claim does not replace the sample already on screen.
- `View.appEntityIdentifier(_:)` associates the sample with its view. `NSUserActivity.appEntityIdentifier` is filled when the host's Info.plist names an activity type (`LabContextCardsActivityType`). The activity is not eligible for Handoff. `isEligibleForPrediction` is unavailable on macOS and tvOS, so it is set only on iOS and watchOS, and it is set to false. Siri suggestions stay a separate gate.
- The snippet uses `IntentResult.result(value:dialog:content:)` and `requestConfirmation(..., content:)`, which resolve when the file imports SwiftUI as well as AppIntents. `Button(intent:)` is the snippet's Set Aside. The hosts that link the module may link `_AppIntents_SwiftUI`. `Config/ProductPolicy.txt` allows that for CoreLocal on macOS and iOS, and the SystemSurfaces line already allowed it for the widget.
- No `AppShortcutsProvider` is declared. Ask About Visible Sample and Set Aside Visible Sample are in the typed Shortcut library. Context resolution's sentence is "Context resolution is unavailable." A Siri-disabled reading of the card is the same card.
- Set Aside is `DomainOperation.archiveItem` through `ActionAtlasActions.archiveItem`, so the grant and the receipt are the existing path. Reset Demo restores a demo sample. Two Mac windows share one published sample: the last one to show a sample is the one a screen-bound decision checks.

## Delivery

[Implementation ticket](../tickets/LAB-002-A.md) → [qualification ticket](../tickets/LAB-002-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S02](../docs/SOURCE_INDEX.md#s02), [S03](../docs/SOURCE_INDEX.md#s03), [S64](../docs/SOURCE_INDEX.md#s64). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
