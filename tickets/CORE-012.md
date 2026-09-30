---
id: "CORE-012"
title: "Qualify the complete first six-lab journey"
status: "blocked"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-006", "CORE-007", "CORE-008", "CORE-009", "CORE-010", "LAB-001-B", "LAB-004-B", "LAB-007-B", "LAB-008-B", "LAB-010-B", "LAB-035-B"]
---

# CORE-012 — Qualify the complete first six-lab journey

## Goal

Prove the lab as a coherent app before growing the catalog into advanced experiments.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** M1 integration tests, showcase route, compatibility/evidence records.

## Implementation steps

1. Run the source/import → proposal/manual review → commit → query → surface journey
2. Exercise model unavailable, permission denied, duplicate import, stale state, and cancellation
3. Validate both physical supported adapters and the complete CoreLocal alternate route
4. Record tested hardware/OS and explicitly untested profiles

## Acceptance criteria

- [x] One shared object remains consistent across every tested entry point.
- [x] The manual path completes the entire workflow without cloud inference.
- [x] A demo reset preserves user-imported data.
- [x] No optional feature failure becomes a crash or unexplained dead end.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State: blocked on one run, the journey on the physical iPhone.** Everything else is done. The phone moved to another host and is in use by another team, so this ticket did not install on it or drive it; the run below is pending and needs a device slot. No experiment's state changes: all six stay `implemented`.

**What the lab can now show.** The first six-lab journey on one shared object, the note with injected instructions, is one route ([showcase 01](../showcases/01-the-app-that-meets-you-halfway.md)): paste it, add it to a collection of your own, review a proposal from it (model, sample parser, or by hand), find, rename, archive, and restore it, change the session, finish the accessible task, carry it, and Reset Demo, which leaves it alone. The route ran end to end in the real Mac app on the development Mac.

**Acceptance.**

- [x] One shared object stays consistent across every tested entry point. Fixture: `FirstJourneyTests` reads the object after each of the journey's 11 steps through the service as the app UI, App Intent, model-tool, and share-extension adapters, the action browser, the App Intent entity, Export Lab Item's JSON, and the `.anlab` document, and each reads what the store holds; the paste, share-extension, and CoreLocal routes end in identical state and byte-identical exports. Physical, Mac app UI only: the same identifier and revisions 1 to 4 in Share Inbox, Action Atlas (Find, Update, Archive, Restore, Get), and the Portable Objects preview.
- [x] The manual path completes the whole workflow without cloud inference. Fixture: the CoreLocal route (no share-extension folder, no widget or Control, the model probe routed to the fallback, the manual editor) ends in the same state as the parser route, with every change committed by the app or an App Intent; a source scan finds no URL loading, socket, CloudKit, Private Cloud Compute, or web view in the six modules, LabDomain, LabStaging, LabStore, or the journey's host folders. Physical: the Mac run used Write It Myself with the model available, and its store holds only app-UI receipts.
- [x] A demo reset preserves user-imported data. Fixture: at the end of every route, mid-journey with an import waiting, an object review open, practice set up, and the session running, and in the SQLite replay. Physical: the Mac's Reset Demo restored 6 samples and paused the session, and the pasted object stayed at revision 4 in Field notes.
- [x] No optional feature failure becomes a crash or an unexplained dead end (fixture and Mac). Five closed model gates and eight ways a model can fail while drafting each name themselves and leave the manual editor, which completes the step; an intent or Control with no connected store, and a damaged widget snapshot, say what to do; denials, duplicates, stale decisions, and cancellation at every step change nothing and leave the next step usable. On the Mac, an empty collection title was refused with a sentence and no receipt, and nothing crashed. Not seen on an iPhone.

**Tightened from the resumed branch.** The journey checked the object only at its end, and its "CoreLocal" route still used the widget and the Control. Now every entry point is compared after every step, the CoreLocal route has no share extension, widget, or Control and asserts its adapters, and the tests add the model's in-flight failures, the network scan, and `theShowcaseScriptIsExactlyTheJourneysChanges`, which ties the package journey to the SQLite replay operation by operation.

**The run that is pending (iPhone).** From this branch's final commit, on the Mac the iPhone is attached to:

1. Before installing, copy the installed app's store read-only (`xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer --domain-identifier <installed bundle ID> --source "Library/Application Support/Native Lab" --destination <private folder>`) and note its aggregates: collections and items per namespace, archived counts, receipts by operation, adapter, and status.
2. `script/install_phone.sh <device-id>`: LabPhone-Core, Debug, CoreLocal, signed with the ignored `Config/Local.xcconfig` so the installed bundle identifier is unchanged. The launch must not crash, and the person's existing items must still be there.
3. The person runs the route's eight steps on the phone with Write It Myself: Import tab Paste (the note fixture, or any short text), New Collection…, Add; Typed Local Intelligence; Actions tab Find, Update, Archive, Restore; Surface Deck Start, Pause, Start; Access as a Superpower Set Up Practice and one restore; Portable Objects preview; Reset Demo; Get Lab Item.
4. Copy the store read-only again and compare. Pass if: the new item exists once in the person's collection at revision 4, unarchived; its receipts are Create, Update, Archive, and Restore Item only; every new receipt is committed as App UI; the last Reset Demo left every item of the person's own unchanged; no demo item is archived and the session is paused.
5. Publish aggregates and hashes only, never typed text, through `DeviceRunEvidence` (`LAB_DEVICE_RUN_FACTS`, with the installed build's Info.plist), as `evidence/CORE-012/first-journey-iphone-in-app.json`; then set this ticket `done`.

**Changed:** `Packages/LabFeatures/Tests/FirstJourneyTests/` (the journey, its routes and failure cases; the target was added to `Packages/LabFeatures/Package.swift` on the resumed branch), `Packages/LabFeatures/Sources/FirstJourney/` and its `FirstJourney` library product (the journey's fixed values only, linked by no host: without a product, Xcode gave the test target a scheme with no destination, which the release manifest refused in the first `script/test.sh` run), `Packages/LabDemo/Tests/LabDemoTests/FirstJourneyShowcaseTests.swift`, `Fixtures/showcase/first-journey/` and its README section, `evidence/CORE-012/` (2 records), and `showcases/01-the-app-that-meets-you-halfway.md` (the route, tested hardware, and untested profiles). No shared host file, `project.yml`, or entitlement changed.

**Commands and results:** see the CORE-012 rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Platforms:** Mac passed (fixture, and physical for the Mac host's app UI). iPhone: pending physical; each step passed in the simulator in its own ticket, but the route as one journey has not run there. Watch and TV not applicable.

**Not run:** the route on a physical iPhone (pending) and on any iPad; the share extension, App Group staging, widget, and Control on a device (blocked by Personal Team signing); App Intents from Shortcuts or Siri on a device; the on-device model in this route; a file export and import in the Mac run; a person with VoiceOver, Voice Control, or Full Keyboard Access; a 26-family SDK compile.

**Follow-ups:** Reset Demo's confirmation reads "Your data (1 collections, 1 items)"; the Mac Lab menu's Reset Demo… is disabled while the app has no key window, as its other window commands are; the Mac review drafts from the host's bundled copy of a note, never from a stored item; the pasted-then-shared duplicate is still refused with advice to share again (LAB-007-B's known issue, pinned by `theSameNoteSharedAfterItWasPastedIsNotStoredTwice`).

**Next dependency-ready tickets:** CORE-011 once this ticket is done; LAB-030-A and LAB-043-A.

