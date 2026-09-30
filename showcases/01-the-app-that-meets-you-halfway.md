# Showcase 01 — The app that meets you halfway

## Audience payoff

Begin with a shared original note, inspect a typed or manual proposal, commit one object, find it through a native action, and reflect safe state in a user-added surface.

## Components

- [001 — Action Atlas](../experiments/LAB-001-action-atlas.md)
- [007 — Share Ingress Station](../experiments/LAB-007-share-ingress-station.md)
- [008 — Portable Objects](../experiments/LAB-008-portable-objects.md)
- [010 — Typed Local Intelligence](../experiments/LAB-010-typed-local-intelligence.md)
- [004 — Surface Deck](../experiments/LAB-004-surface-deck.md)
- [035 — Access as a Superpower](../experiments/LAB-035-access-as-a-superpower.md)

## What's real and what's simulated

[CORE-012](../tickets/CORE-012.md) qualified this route. Read this first, because it decides what the rest of the page can claim.

- **The whole route ran in the real Mac app, on a Mac.** An agent drove it through the Accessibility API on the development Mac (Mac Studio, M5 Max, macOS 27.0), with the manual editor and no model, from the paste to Reset Demo. No person used a pointer or keyboard for that run. [Record](../evidence/CORE-012/first-journey-mac-running-app.json).
- **On iPhone it has not run as one journey yet.** Parts of it ran on a physical iPhone 16 Pro in earlier tickets (Action Atlas's in-app actions, LAB-001-B), and each part ran in the iOS Simulator in its own ticket. The whole route on the iPhone is pending.
- **The share extension, the widget, and the Control have never run on a device.** They need a team that can sign App Groups. On a device the route uses Paste, the app's own Surface Deck, and Shortcuts instead.
- **Every entry point was compared in tests, not by a person.** `FirstJourneyTests` runs the route through the six modules, reads the object through every entry point after each step, and compares them. A replay of the route's changes runs on the lab's SQLite store. Both are fixture results.

## The route

Start with a clean install, or press Reset Demo first. Nothing here needs an account, a network connection, or a second device. On a Mac, run `script/build_and_run.sh`; the sidebar and ⌘1–⌘8 reach every page. On iPhone, the Import and Actions tabs hold the inbox and Action Atlas, and the Catalog tab opens the other experiments.

1. **Share a note (LAB-007).** Copy the original note in [`Fixtures/intelligence/intelligence-injected-note.txt`](../Fixtures/intelligence/README.md) and press Paste in the Share Inbox. Its second paragraph tries to give the app orders. It waits for review as text, from Paste, and nothing is stored yet.
2. **Make it yours.** On its review screen, choose New Collection…, name it Field notes, and press Add to Collection. The receipt says one item was created in Field notes, as App UI. The note's first line is its title. Its instructions did nothing: no other receipt appears.
3. **Review a proposal (LAB-010).** Open Typed Local Intelligence and choose the note with injected instructions. Draft with the on-device model or the sample parser, or choose Write It Myself: sample Kraft card, and the note's first line as the added text. Nothing changes until you press Apply Change. The sample chooser lists only demo samples, so the note can't make the app change your own item.
4. **Find it and act on it (LAB-001).** In Action Atlas, Find Lab Items for "override" finds exactly one item, yours. Rename it with Update Lab Item, archive it, and restore it. Its identifier stays the same, and its revision goes from 1 to 4. The same actions are in Shortcuts.
5. **Change a surface (LAB-004).** In Surface Deck, start, pause, and start the demo session. The previews show what a widget and a Control would read: the session's state, never your item.
6. **Finish the task (LAB-035).** Set Up Practice, then restore Quartz point from Mineral specimens, by sight, VoiceOver, keyboard, or Audio Graph. The page says "Task: Done". Your item isn't in the task: it counts demo collections only.
7. **Carry it (LAB-008).** In Portable Objects, select your item: its export has the same identifier and revision. Export it, and importing that file again says it's already in this lab.
8. **Reset Demo.** The confirmation says your data won't change. Afterwards the demo samples are back as they were, the session is paused, and your item is still in Field notes, renamed, at revision 4.

**The failure to repeat.** Do steps 1 to 8 again with the model off, or on a device without Apple Intelligence: the Typed Local Intelligence page says why the model isn't offered, and Write It Myself completes the same step with the same change. The Mac run above took this path on purpose, with the model available.

## Tested hardware and software

| Where | What ran | Result | Evidence |
|---|---|---|---|
| Mac Studio (Mac17,14, M5 Max), macOS 27.0 (26A425) | The running Mac app, CoreLocal Debug at d7b386a, driven through the Accessibility API; manual editor | passed, physical, Mac host only | [first-journey-mac-running-app](../evidence/CORE-012/first-journey-mac-running-app.json) |
| The same Mac, Xcode 27.0 (27A266a), macosx27.0 | `FirstJourneyTests` (the route, its CoreLocal variant, and its failure cases, in memory) and the SQLite replay | passed, fixture | [first-journey-showcase-app-ui](../evidence/CORE-012/first-journey-showcase-app-ui.json) |
| iPhone 16 Pro (iPhone17,1), iOS 27.0 (24A5430a) | Not run for this route; LAB-001-B's in-app actions ran there earlier | pending | [LAB-001 record](../evidence/LAB-001/action-atlas-iphone-in-app.json) |
| iOS Simulator, iOS 27.0 | Each step in its own ticket, not the route as one journey | passed per step, simulator | the LAB-004, 007, 008, 010, and 035 records |

## Not tested

- **The route on a physical iPhone or iPad**, and any iPad at all.
- **SystemSurfaces on a device:** the share extension, App Group staging, the widget, and the Control. Blocked: a free Personal Team cannot sign App Groups.
- **App Intents from Shortcuts or Siri on a device.** The package tests run the same intent types; the Mac run used the in-app actions.
- **The on-device model in this route.** It ran in LAB-010-B on the Mac; here the manual editor stood in for it on purpose.
- **A person with VoiceOver, Voice Control, or Full Keyboard Access** following the route.
- **A 26-family SDK build**, macOS or iOS 26, an Intel Mac, and any other Mac or iPhone model.
- **Watch and Apple TV:** they have no M1 journey surface.

## Demonstration contract

Start from a named fixture and declared device configuration. Show the actual action, result, and operation receipt before opening the mechanism inspector. Repeat one meaningful failure or unavailable path. End by restoring demo-owned state. Record only approved media and attach the corresponding evidence run.

## Boundaries

No second device or cloud route is required. The failure demonstration disables the model and repeats the same successful journey manually.

This page describes a qualified route, not a recording. No screenshot or video of it has been made.
