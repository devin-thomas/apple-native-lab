# Context Cards: a walkthrough

Context Cards shows an original sample, lets you prepare a decision, and refuses that decision if a different sample replaces it. Set Aside archives through Action Atlas with an authorization check, a receipt, and an undo.

## What was checked

**Context resolution is unavailable in this build.** No Apple schema is adopted for a pigment swatch. The checks run the fallback logic in package tests and the sandboxed Mac host with fresh SQLite stores. They do not prove Siri, a system snippet, the Shortcuts app, or a Siri-disabled device's system presentation. The experiment stays `implemented`.

The Siri-off check compares the same `DecisionCard` value with `siriEnabled` true and false. It is a fixture check, not a change to the Mac's or a phone's Siri settings. The host always requests the false value. Typed intents were called through `run(with:)`, with a stand-in for confirmation.

## Try the fallback

On Mac, choose View › Context Cards (⌥⌘2), or Context Cards in the sidebar. On iPhone, choose Context Cards in Catalog, then Open Context Cards. The iPhone instructions describe the implemented surface; this qualification did not drive that experiment's screen in a simulator or on a phone.

1. Start with Reset Demo. Amber swatch says “On screen.” The card says “Context resolution is unavailable.”
2. Press Set Aside… and then Cancel. Nothing changes and no receipt is added.
3. Press Set Aside… again, then Show the other sample. Cobalt replaces Amber; the pending decision still names Amber. Press Set Aside. The decision is refused, and neither sample is archived.
4. Cancel the old decision. Show the first sample, prepare a new decision, and confirm it. Amber says “Set aside.” The receipt offers an undo.
5. Reset Demo restores Amber. Imported records belong to the user namespace and remain intact.

Ask About Visible Sample and Set Aside Visible Sample are typed intents. They name a sample explicitly; there is no curated Context Cards App Shortcut. A generation-bound card refuses a replacement before and after confirmation. An explicitly named intent without a generation deliberately addresses that named item independently of the screen.

## Qualification boundaries

| Check | Evidence path | Meaning |
|---|---|---|
| Replacement before and during confirmation | Package fixture; Mac hosted stale check and session replay | Neither sample changes; stale session adds no receipt |
| Schema mismatch | Package fixture | Every recognized domain, an unknown domain, and a blank claim fail; the board keeps its old sample |
| Siri-off card | Package fixture | Set Aside, Cancel, and unavailable wording remain identical |
| Cancel, duplicate, reset | Mac hosted fixture | Cancel leaves no receipt; retry and duplicate return one receipt; reset preserves an imported original note and its receipt |
| Missing authorization grant | Package fixture | The underlying archive operation refuses the ungranted commit with no mutation or receipt |

Commands and results are recorded in [BUILD_STATUS](../BUILD_STATUS.md); retained records are in [evidence/LAB-002](../../evidence/LAB-002/).

## Accessibility, privacy, and rights

Source review: the card combines its title, note, and status; refusal has visible words and an accessibility label beginning “Problem”; confirmation has Return and Escape shortcuts and action hints. The Mac entry has a menu command. Show the other sample and Set Aside… have no dedicated menu commands. No manual VoiceOver, Voice Control, Full Keyboard Access, large-text layout, or accessibility audit ran for Context Cards.

Inputs are the original bundled demo seed and an original synthetic import note. Tests use temporary stores, never a private account or the app's existing store. No screenshots, recordings, or media exports are included. The retained JSON contains fixture hashes and observed outcomes; it contains no store path, account, or device serial number. No cloud route or permission request is added. Both intents require authentication; no system authentication dialog was exercised.

Two Mac windows share one published context. The last window to publish controls a screen-bound decision; leaving either page clears it. That limitation remains. iPad, physical iPhone, system snippets, Siri, Shortcuts, region availability, and a 26-SDK compile remain not-run.

Apple's [App Schemas session](https://developer.apple.com/videos/play/wwdc2026/240/) explains schema-based contextual integration. The lab's deliberate schema refusal must not be advertised as that live integration. [Siri availability](https://support.apple.com/en-gw/127893) remains a separate gate from compiling an intent. See the [installed-SDK ledger](../VERIFICATION_BOUNDARIES.md#context-cards-lab-002).
