---
id: "LAB-002-A"
title: "Implement Context Cards"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-002-A — Implement Context Cards

## Goal

Ask about the visible object, then complete a small decision inside a system presentation.

## Authority and scope

Read the [governing specification](../experiments/LAB-002-context-cards.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** context-cards module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Associate one primary sample entity with its view
3. Map only genuinely matching Apple schemas
4. Render an interactive confirmation where supported
5. Resolve stale visible content without touching a different object
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] A replaced onscreen item cannot mutate the previous item. (`ContextCardsOperationTests.aReplacedSampleCannotChangeThePreviousOne` and `replacingTheSampleDuringConfirmationDoesNotChangeIt`; hosted `ContextCardsHostTests.aReplacedOnscreenSampleCannotMutateThePreviousOneThroughTheHost`. A decision bound to generation N is refused when the screen shows generation N+1, before confirmation and again after it, and neither sample is archived.)
- [x] A schema mismatch fails the integration gate. (`ContextCardsSchemaTests`: every installed `AppSchema` domain with sample entity names, an invented domain, and a blank claim are mismatches; `aMismatchedClaimDoesNotReplaceTheSampleOnScreen` leaves the previous sample on the board.)
- [x] Siri-disabled devices retain the same decision UI. (`ContextCardsSurfaceTests.aSiriDisabledDeviceKeepsTheSameDecisionCard`: `DecisionCard.showing(siriEnabled:)` returns the same card for true and false, with Set Aside and Cancel.)
- [x] Fallback is usable: In-app card and typed Shortcut remain complete; context resolution is explicitly unavailable.. (In-app Set Aside archives through Action Atlas with a receipt; Ask About Visible Sample and Set Aside Visible Sample are typed App Intents with no `AppShortcutsProvider`. Every dialog and card includes "Context resolution is unavailable." Package and hosted Ask/Set Aside paths prove it.)
- [x] Sensitive operations share the domain authorization/receipt path. (`ContextCardsActions.setAside` calls `ActionAtlasActions.archiveItem` → `DomainOperation.archiveItem` with the entry-point adapter; hosted set-aside leaves an App UI receipt with an undo in the session list.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No invented universal schema for arbitrary business nouns; Siri rollout and region are separate gates.

**Research:** [S02](../docs/SOURCE_INDEX.md#s02), [S03](../docs/SOURCE_INDEX.md#s03), [S64](../docs/SOURCE_INDEX.md#s64).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-002's spec now claims `implemented`. The in-app card and the typed Shortcut domain path ran through package tests and Mac hosted tests. Context resolution stays unavailable: no Apple schema is adopted for a lab sample. Nothing here is device-verified, and Siri and the Shortcuts app were not opened.

**Installed SDK (Xcode 27.0, iOS 27.0 / macOS 27.0).** The iOS 27.0 `AppIntents` interface lists `AppSchema` domains audio, books, browser, calendar, clock, files, journal, mail, maps, messages, notes, phone, photos, presentation, reader, reminders, spreadsheet, whiteboard, and wordProcessor. None matches a lab sample. `View.appEntityIdentifier(_:)`, `NSUserActivity.appEntityIdentifier`, `IntentResult.result(value:dialog:content:)`, and `requestConfirmation(..., content:)` are in `_AppIntents_SwiftUI`. Findings are in the [installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md#installed-sdk-ledger).

**Changed:**

- `Packages/LabFeatures`:
  - The `ContextCards` product and target (new), depending on ActionAtlas and LabDomain: `VisibleEntityContext`, `DecisionProposal`, `DecisionCard`, `ContextBoard`, `SchemaGate`, `ContextCardsActions.setAside`, `AskAboutVisibleSampleIntent`, `SetAsideSampleIntent`, the snippet, and `View.visibleSample`. No new `DomainOperation`.
  - `ContextCardsTests` (new): schema gate, stale generation, cancellation, invalid request ID, unavailable path, Siri-disabled card, and Ask intent.
- `Apps/Shared/ContextCards/` (new): `ContextCardsHost.connect`, `ContextCardsSession`, the card page, and the catalog launch.
- `Apps/Mac/Window/ContextCardsColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState` has `.contextCards` and the per-window session.
  - `MainWindow` has the columns and the search prompt.
  - `SidebarView` has the row.
  - `LabCommands` has View › Context Cards (⌘9).
  - `ExperimentDetailView` has Open Context Cards.
  - `LabMacApp` and `LabPhoneApp` call `ContextCardsHost.connect`.
  - `ActionAtlasHost` includes `ContextCardsIntentsPackage`.
- `project.yml` and the regenerated project (byte-identical over two runs): LabMac, LabPhone, and LabPhoneSurfaces link `ContextCards`; each declares `LabContextCardsActivityType` and `NSUserActivityTypes`.
- `Config/ProductPolicy.txt`: CoreLocal on macOS and iOS may link `_AppIntents_SwiftUI` for snippets and `Button(intent:)`.
- `Tests/LabMacTests/ContextCardsHostTests.swift` (new). `ActionAtlasHostTests` expects the two Context Cards intents (13 actions total).
- Catalog: `experiments/LAB-002-context-cards.md` (`state: implemented`, split, notes) and regenerated `experiments.json`. Catalog tests expect 7 implemented and 41 specified.
- `docs/SOURCE_INDEX.md`, `docs/VERIFICATION_BOUNDARIES.md`, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** Installed `AppSchema` domains and the `_AppIntents_SwiftUI` snippet/confirmation symbols were read on research; none was adopted for a lab sample.
2. **Associate.** Amber swatch is the primary sample; Cobalt replaces it. `View.visibleSample` sets `appEntityIdentifier` and, when the host names an activity type, fills an `NSUserActivity` that is not eligible for Handoff or prediction.
3. **Schemas.** `SchemaGate` refuses every claim for `.labSample`. A refused claim leaves the board unchanged.
4. **Confirmation.** The in-app card asks Set Aside / Cancel. The Shortcut uses `requestConfirmation` with the same card content. The snippet's button is `Button(intent:)`.
5. **Stale content.** Decisions carry the screen generation. Replacement before or during confirmation throws `staleVisibleContent` and archives nothing.
6. **Tests.** Domain/adapter coverage above, plus hosted set-aside, stale refusal, Ask, activity type, and sidebar destination.

**Not run:**

- A physical device.
- Siri, and the Mac or iPhone Shortcuts app (a person's library).
- AppIntentsTesting system-path tests (need a signing team).
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- iPad, Watch, and TV surfaces for this experiment (hosts are Mac and iPhone).
- A 26-SDK compile.

**Known limitations:**

- Two Mac windows share one published sample on `ContextCardsHost.link`; the last window to show a sample is the one a screen-bound decision checks. Leaving a window clears the published sample.
- No curated App Shortcut; Ask and Set Aside stay in the typed library.
- Context resolution is always unavailable in this build by design.

**Next dependency-ready ticket:** LAB-002-B (qualification). It needs this ticket, and CORE-007, CORE-009, and CORE-010.
