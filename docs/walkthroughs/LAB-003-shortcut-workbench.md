# Shortcut Workbench qualification

LAB-003 remains `implemented`. This qualification distinguishes the local recipe runner from the Shortcuts app. Package tests invoke domain operations and intent helpers; hosted tests invoke the app’s backend and model. Neither is a system Shortcuts run. No iPhone or iPad hardware is used.

## Try the local fallback

1. Open Native Lab, then Shortcut Workbench (Mac: View menu, ⌥⌘8; iPhone: the experiment’s Open Shortcut Workbench link).
2. Read the manual recipe cards and the six curated entry descriptions. Action Atlas is the larger atomic action browser.
3. With the original demo seed present, select Import → Query → Transform → Export and choose Run Recipe. The UI chooses an existing demo item when no source is bound, removes the import step, and runs query → transform → export. This changes that item’s note through the operation service; it does not import a file.
4. Choose Export Recipe to inspect the definition. The export is recipe JSON, not an exported item or an installable `.shortcut`. Model inspection is a local preview; no model is called.
5. Rename the bound source using Action Atlas and resolve it again by ID. Reset Demo restores demo items; it preserves imported user items. Authored recipes are held for this process only.

These are instructions derived from the implemented views. The qualification does not claim a person drove these controls or reviewed their assistive-technology behavior.

## Bound fixture replay

The qualification stages and commits original text into a fresh user collection, binds that item’s ID to a recipe, removes the completed import step, renames the item, and runs query → transform → export. It checks the receipt, the retained ID, cancellation of another staged import, and Reset Demo leaving the user item unchanged. The Mac and iPhone hosted test source uses the same checks against each host’s real SQLite backend. Evidence records identify which runs actually completed.

## Fresh recipe

The bundled Import → Query → Transform → Export recipe also runs unbound, as the Run Import–Export Recipe intent does when given a collection and no source item. The run is planned before it changes anything: the collection, import title and note, query text, the transform's source and resulting note, and the step order. A recipe that cannot complete (a transform with nothing to transform, a transform before the import, two imports, a missing collection or bound item, an oversized note or query) is refused with nothing staged or committed. A recipe that imports transforms the item it imports, so the transform rides on the import's one `createItem`; the new item is then bound as the recipe's source. A run commits at most one operation, so it never stops half-way.

## What an export contains

An export writes the format, the recipe's ID, each step's order and kind, and the IDs of the items it uses. It writes a title, a step's detail, or a model-step field name or value only when that string is exactly text the lab ships in its bundled recipes. Anything a person or caller typed is withheld, whatever its field is called: a typed value is written as `[withheld]`, and a model-step field whose name was typed is only counted. The export message and the Export Recipe intent's dialog say what was withheld. The Inspect Model Step intent's result follows the same rule. The in-app inspection still shows typed values, masking secret-shaped field names.

## Known limits

- Person-authored recipes export as structure and IDs only. There is no reviewed opt-in to include typed text.
- A completed bound recipe is not idempotent: its transform uses a new request ID on each run and can append its suffix again. A fresh run's import and transform share the run's request, so a retry replays the first receipt.
- Cancellation before the run's one commit leaves nothing. After that commit the run finishes its read and export steps rather than stopping.
- A bound run from the app or the intent saves the bound copy over the walkthrough in the session catalog, so a later unbound run of that recipe in the same session runs the bound copy.
- Recipes are process-local; export preserves IDs but no recipe-file importer or cross-device store exists here. A saved system shortcut surviving rename, Shortcuts Storage, Siri, and model transcript inspection remain unverified.

## Privacy, rights and accessibility review

Only original fixture text, fixed sample identifiers, synthetic sentinels, source hashes, and test evidence belong in this qualification. There are no screenshots, recordings, credentials, private stores, real accounts, or personal shortcuts to publish. No network/model/Storage adapter is exercised by the recipe tests.

Static accessibility review: native List, NavigationLink and Button controls use visible labels and system fonts; the Mac has a navigation menu shortcut. Recipe action buttons launch work in a Task without a Cancel control or retained cancellation owner. Mac selection replaces the overview with a detail page, so the list’s manual fallback shows titles rather than complete instructions until the overview is restored. Latest results appear on the overview, while actions run on the detail page. These require a UI and assistive-technology pass. VoiceOver, Voice Control, Full Keyboard Access, large text, reduced motion and an automated UI audit are not-run.

## Runs needed for live qualification

On an isolated Mac test profile or an owner-approved iPhone: build a personal shortcut that stores an original lab item entity, rename it in Native Lab, run Resolve Lab Item and compare its stable ID. Separately test cold-start discovery, protected-action authentication, six curated entries, cancellation, and exports through Shortcuts. Do not inspect unrelated personal shortcuts or enable automations. iPad, cross-device Storage, Siri and OS 26 need separate evidence. Physical mobile runs belong to the owner.

## Captured results (2026-10-01)

The narrow package run passed 21 tests; two characterization tests reproduce failed interactions, recorded separately. The full four-platform gate passed at `addbf39-dirty`. The bound hosted check passed on Mac Studio / macOS 27.0 (26A425) and iPhone 18 Pro simulator / iOS 27.0 (24A434). Both produced the same original bound-recipe SHA-256, `b56d8deb688e0634b16a5bed6ad2d23f75b99ea16a069b3da94fd1d9515bf39c`.

See [the six evidence records](../../evidence/LAB-003/) and [completion record](../../tickets/LAB-003-B.md). The hosted records keep `execution.path: fixture`: calls ran in process against fresh SQLite stores, with no system Shortcuts or UI control invocation. The simulator record identifies its environment explicitly. The fresh unbound recipe and unrestricted export-safety check remain failed; system and manual gates remain not-run. No physical mobile device evidence or release promotion is claimed.
