# Showcase fixtures

Original, public-safe demonstrations that `Packages/LabDemo` replays (CORE-009). Everything here is synthetic, written for this project, and distributed under the repository's MIT License. Every script declares the `public-fixture` data tier, so an evidence export includes it without an override ([SECURITY_AND_PRIVACY](../../docs/SECURITY_AND_PRIVACY.md), [ASSET_POLICY](../../docs/ASSET_POLICY.md)).

## `atlas-basics/`

A replay in the spirit of [LAB-001](../../experiments/LAB-001-action-atlas.md), entirely in the demo namespace:

| Step | What it does |
|---|---|
| `approve-reset`, `reset` | The person confirms Reset Demo, which creates the 2 collections and 5 items of `seed.json` in the demo namespace. This is the only way anything is created there ([ADR-012](../../docs/adr/ADR-012.md)). |
| `list-shoreline`, `find-glass` | Read through the service: one collection ordered by title, then a text search. |
| `rename-glass`, `find-frosted` | Rename the sea glass sample at revision 1, then find it by its new title. |
| `approve-archive`, `archive-glass`, `find-after-archive` | The person confirms, the sample is archived at revision 2, and a search no longer shows it. |
| `undo-archive`, `find-after-undo` | Submit the undo operation recorded in the archive receipt, and the sample appears again. |

The seed's IDs and the request IDs are stable UUIDs generated once at random for this fixture. Never change or reuse one. Changing any byte of either file changes its input hash, and with it the replay fingerprint and every receipt ID.

## `action-atlas/`

The complete [LAB-001](../../experiments/LAB-001-action-atlas.md) fixture interaction, from a clean store, for the LAB-001-B qualification. Its `seed.json` is a byte-for-byte copy of the app's demo seed, [`Fixtures/demo/seed.json`](../demo/seed.json), so it starts from the same 12 samples the app seeds on its first run. `ActionAtlasShowcaseTests` in `Packages/LabDemo` fails if the two copies differ.

| Step | What it does |
|---|---|
| `approve-reset`, `reset` | The person confirms Reset Demo, which creates the 3 collections and 12 items of the seed in the demo namespace. |
| `create-collection`, `create-item` | Create one of the person's own collections, Field notes, and an item in it, Graphite stick. Their IDs are the ones Create Lab Collection and Create Lab Item derive from the same request IDs. |
| `find-graphite`, `find-swatches` | Find the new item by text, then list the Pigment swatches collection by title. |
| `update-item`, `update-sample`, `find-renamed` | Rewrite the new item's note, rename the amber sample, and find it by its new title. |
| `approve-archive`, `archive-item`, `find-after-archive`, `find-archived` | The person confirms, the new item is archived, a search no longer shows it, and a search that includes archived items still does. |
| `undo-archive`, `find-after-undo` | Submit the undo recorded in the archive's receipt, and the item appears again. |
| `approve-reset-again`, `reset-again`, `find-after-reset`, `find-yours-after-reset` | A second Reset Demo restores the renamed sample and leaves the person's collection and item exactly as they were. |

The same script is replayed three ways:

- by `Packages/LabDemo` as evidence, once composed as the app-UI adapter and once as the App Intent adapter (no intent type runs there);
- through the Action Atlas actions and App Intent types in `ActionAtlasShowcaseReplayTests` (`Packages/LabFeatures`);
- in the Mac app by `ActionAtlasHostEvidenceTests`, with the same request IDs.

The request IDs were generated once at random for this fixture. Never change or reuse one.

## `typed-intelligence/`

The [LAB-010](../../experiments/LAB-010-typed-local-intelligence.md) fixture interaction, from a clean store, for the LAB-010-B qualification. Its `seed.json` is a byte-for-byte copy of the app's demo seed, like `action-atlas/`'s. Its two edits are the sample parser's drafts of the original notes in [`Fixtures/intelligence/`](../intelligence/README.md), approved unedited. A replay cannot run a model, so the model's drafts are recorded separately and never replayed.

| Step | What it does |
|---|---|
| `approve-reset`, `reset` | The person confirms Reset Demo, which creates the 3 collections and 12 items of the seed in the demo namespace. |
| `find-blue` | Search for "blue", the word the lookup tool is given for "the blue one": the cobalt and the verdigris swatches. |
| `apply-cobalt`, `find-bleeds` | Apply the parser's draft of the ambiguous note: rename the cobalt swatch to the note's quoted title, "Cobalt (bleeds)", and add the note on a new line. Then find it by its new title. |
| `undo-cobalt`, `find-after-undo` | Submit the undo recorded in the change's receipt, and the rename and the added text are gone. |
| `apply-kraft`, `find-fray`, `find-override` | Apply the parser's draft of the note with injected instructions: one added line on the kraft card, from the note's first paragraph only. A search for "override", archived items included, finds nothing. |
| `approve-reset-again`, `reset-again`, `find-after-reset` | A second Reset Demo restores the kraft card, the only sample still different from the seed. |

The script is used two ways:

- by `Packages/LabDemo` as evidence, composed as the app-UI adapter, the adapter a person's Apply commits as. The same tests replay it as the model-tool adapter, which can change nothing, and with a stale revision and a cancellation;
- by `TypedIntelligenceQualificationTests` in `Packages/LabFeatures`, which drafts both notes through the real flow and checks that the approvals are exactly the script's two edits.

The LAB-010 evidence export carries this replay beside the records of the live model runs and the model-unavailable run, so every record passes the same rights review. The [walkthrough](../../docs/walkthroughs/LAB-010-typed-local-intelligence.md) says which result came from where.

The request IDs were generated once at random for this fixture. Never change or reuse one.

## `access-superpower/`

The complete [LAB-035](../../experiments/LAB-035-access-as-a-superpower.md) fixture interaction, from a clean store, for the LAB-035-B qualification. The task is "Which demo collection has the most archived samples? Restore one sample from that collection." Its `seed.json` is a byte-for-byte copy of the app's demo seed, [`Fixtures/demo/seed.json`](../demo/seed.json), and its six practice samples are the ones [`Fixtures/access/archive-chart.json`](../access/README.md) lists. `AccessSuperpowerShowcaseTests` in `Packages/LabDemo` fails if the two seed copies differ.

| Step | What it does |
|---|---|
| `approve-reset`, `reset`, `find-minerals-first` | The person confirms Reset Demo, which creates the 12 samples. Nothing is archived yet, so the task has no answer. |
| `approve-practice-*`, `practice-*` | Set Up Practice: 6 archives in the practice set's order, each with its own approval and receipt: 3 mineral specimens, 2 pigment swatches, and 1 paper stock sample. |
| `find-pigments-active`, `find-minerals-active`, `find-paper-active`, `find-minerals-with-archived` | The chart's numbers as reads: 2, 3, and 1 of 4 archived. Archiving deletes nothing. |
| `restore-quartz`, `find-minerals-after-restore` | The task's one operation: restore Quartz point from Mineral specimens at the revision the chart showed. |
| `approve-undo-restore`, `undo-restore`, `find-minerals-after-undo` | The receipt's undo archives it again, so the task is to do again. |
| `restore-vellum`, `find-paper-after-miss` | A miss: a restore from Paper stock is a real change with a receipt, but it does not finish the task. |
| `create-collection`, `create-item`, `approve-archive-yours`, `archive-yours` | The person's own collection and item, archived. The task counts only demo collections. |
| `approve-archive-amber`, `archive-amber` | The person archives a demo sample that is not in the practice set. |
| `reset-practice-*` | Reset Practice: restores the 5 practice samples still archived, in the practice set's order. |
| `find-pigments-after-reset`, `find-minerals-after-reset`, `find-yours-after-reset`, `find-yours-with-archived` | Amber swatch and the person's item stay archived; every practice sample is active. |

The same script is replayed two ways:

- by `Packages/LabDemo` as evidence, as the app-UI adapter;
- through the AccessSuperpower module in `AccessSuperpowerShowcaseReplayTests` (`Packages/LabFeatures`), which checks that Set Up Practice, the task's restore, the miss, and Reset Practice build exactly these operations, and that the chart and the task's result read as the chart fixture says.

The request IDs and the person's collection and item IDs were generated once at random for this fixture. Never change or reuse one.

## `share-ingress/`

The [LAB-007](../../experiments/LAB-007-share-ingress-station.md) fixture interaction, for the LAB-007-B qualification. Its `seed.json` is a byte-for-byte copy of the app's demo seed; `ShareIngressShowcaseTests` in `Packages/LabDemo` fails if the two differ.

`intake/` holds what is pasted, chosen, and shared. Every file is original and synthetic, made for this project:

| File | What it is |
|---|---|
| `harbor-walk.txt` | The note: "Harbor walk", then "Bring the blue notebook.", with no final line break |
| `gull-count.txt` | A one-line text file for the file picker |
| `harbor-sketch.png` | A 48 × 32 drawing of a pier over water, written pixel by pixel, with no metadata chunks |
| `tide-clip.mov` | One second of a rising tide line, 64 × 48, 12 frames of H.264, no audio and no metadata items |

The link is `https://example.org/tide-tables`, on a domain reserved for examples.

A replay cannot stage or review, so `script.json` starts where the review ends:

| Step | What it does |
|---|---|
| `approve-reset`, `reset` | The person confirms Reset Demo, which creates the 3 collections and 12 items of the seed. |
| `create-collection` | New Collection… on the review screen creates Field notes, one of the person's own collections. A demo collection cannot take an import. |
| `approve-add-note`, `add-note` | The person's Add on the note: a grant for exactly one new item in Field notes, then the item. Its title is the note's first line, and its note the whole text. |
| `approve-add-link`, `add-link` | The same for the link: with no page title, its title is the host, `example.org`, and its note the address. |
| `find-harbor`, `find-field-notes` | Find the note by a word from it, and list Field notes by title. |
| `approve-reset-again`, `reset-again`, `find-yours-after-reset` | A second Reset Demo finds the demo as seeded, and both imports are still in Field notes, unchanged. |

The two additions' item and request IDs are not chosen: `ImportAdopter` derives them from the content's digest and the collection's ID. They change if a byte of `harbor-walk.txt`, the link, or the collection ID changes, and the tests below fail until the script is updated. The other request IDs and the collection ID were generated once at random for this fixture. Never change or reuse one.

The interaction is run three ways:

- by `Packages/LabDemo` as evidence, from Reset Demo, composed as the app-UI adapter, the adapter a pasted import is added as;
- from the intake in `ShareIngressShowcaseReplayTests` (`Packages/LabFeatures`): the note and the link are pasted and `gull-count.txt` is chosen, and in a second clean lab the link, the note, the image, and the movie arrive in one share through the share extension's folder. Both commit exactly the script's additions and end in the same state;
- in the Mac app by `ShareIngressHostEvidenceTests`, through the inbox's own model, on SQLite.

## `surface-deck/`

The complete [LAB-004](../../experiments/LAB-004-surface-deck.md) fixture interaction, from a clean store, for the LAB-004-B qualification. Its `seed.json` is a byte-for-byte copy of the app's demo seed, and its session ID is the one the app, its widget, and its Controls share. `SurfaceDeckShowcaseTests` in `Packages/LabDemo` fails if either differs.

| Step | What it does |
|---|---|
| `approve-reset`, `reset` | The person confirms Reset Demo, which creates the 12 samples. The session has never been started. |
| `start-session` | Start the session, as the deck's Start Session or a toggle that showed a never-started session does. It is created, running, at revision 1. |
| `pause-session` | Pause it from the revision a surface showed, 1. It is paused at revision 2. |
| `undo-pause` | Submit the undo recorded in the pause's receipt. It runs again at revision 3. |
| `find-swatches` | List the Pigment swatches collection by title: the session's changes touched no sample. |
| `approve-reset-again`, `reset-again` | A second Reset Demo pauses the running session at revision 4 and removes nothing. |
| `start-after-reset` | Start it from the paused state the reset left, revision 4. It runs at revision 5. |

A stale toggle is not in the script. The runner counts a conflict receipt as a step that did not pass, so a stale surface's conflict is proved by the qualification tests instead: `SurfaceDeckQualificationTests` (`Packages/LabFeatures`) and `SurfaceDeckQualificationHostTests` and `SurfaceDeckHostEvidenceTests` in the Mac app. `SurfaceDeckShowcaseTests` also replays a copy with a stale step, to show it is refused and changes nothing.

The request IDs were generated once at random for this fixture. Never change or reuse one.

## `first-journey/`

The [CORE-012](../../tickets/CORE-012.md) first six-lab journey on one shared object, from a clean store, for the M1 qualification and [showcase 01](../../showcases/01-the-app-that-meets-you-halfway.md). Its `seed.json` is a byte-for-byte copy of the app's demo seed; `FirstJourneyShowcaseTests` in `Packages/LabDemo` fails if the two differ. The shared object is [`Fixtures/intelligence/intelligence-injected-note.txt`](../intelligence/README.md), the note whose instructions must stay data; its practice samples are the six that [`Fixtures/access/archive-chart.json`](../access/README.md) lists.

| Step | What it does |
|---|---|
| `approve-reset`, `reset` | The person confirms Reset Demo, the host's first run: the 3 collections and 12 items of the seed. |
| `create-collection`, `approve-add`, `add-object`, `find-override` | LAB-007: New Collection… creates Field notes, and the person's Add commits the pasted note there as one item, its first line the title. A search for the note's injected word finds only the object. |
| `apply-review`, `find-fray` | LAB-010: the reviewed proposal from the object's text, one added line on the kraft card. The sample parser drafts it and the manual editor writes the same change. |
| `rename-object`, `approve-archive`, `archive-object`, `find-after-archive`, `restore-object`, `find-wear-note` | LAB-001: rename the object, archive it with the person's confirmation, and restore it. |
| `start-session`, `pause-session`, `resume-session` | LAB-004: start, pause, and resume the demo session. |
| `approve-practice-*`, `practice-*`, `restore-quartz`, `find-yours-during-task` | LAB-035: Set Up Practice's six archives, then the task's restore of Quartz point. The task counts demo collections only. |
| `approve-reset-again`, `reset-again`, `find-fray-after-reset`, `find-yours-after-reset` | Reset Demo puts back the kraft card, the practice samples, and the session, and leaves the object and Field notes as the person left them. |

The object's item ID and the Add's request ID are not chosen: `ImportAdopter` derives them from the note's digest and the collection's ID. The collection, the Add, the rename, the archive, the restore, and the session's start use the request IDs `FirstJourneyTests` fixes; the other request IDs were generated once at random for this fixture. Never change or reuse one.

The journey is run two ways:

- by `Packages/LabDemo` as evidence, on SQLite, composed as the app-UI adapter;
- by `FirstJourneyTests` in `Packages/LabFeatures` through the six modules themselves, from the paste or the share to the export: `theShowcaseScriptIsExactlyTheJourneysChanges` checks that the journey commits exactly this script's operations, in order. There the rename, the archive, the pause, and the resume are App Intents, and every entry point is read after every step.

## Script format

`script.json` (`format: "native-lab-demo-script"`, `formatVersion: 1`) names its seed, a file in the same folder in the demo seed format that `Fixtures/demo/seed.json` uses. `DemoScript(folder:)` loads both:

- **Reading.** Each file must be an ordinary, visible, singly linked file inside the folder, reached without a symbolic link.
- **Parsing.** Each must be strict JSON with no duplicate keys, and every field must be one the format defines.
- **Steps.** Each step has an `id` and exactly one action:
  - `approve`: the name of a later step.
  - `find`: optional `collection`, `text`, `includeArchived`, and `limit`, and the ordered item IDs it must `expect`.
  - A change, with a `request` UUID: `resetDemo`, one of the domain operations such as `updateItem`, `archiveItem`, or `setSession` (`id`, `running`, and `expected` unless the session was never started), or `undo`, which names an earlier step.
- **Order.** The first change must be `resetDemo`, with the script's own seed.

A script cannot choose its adapter, permissions, or grants. The runner acts as the app UI with that adapter's fixed ceiling ([ADR-011](../../docs/adr/ADR-011.md)). Its only grants are the ones its `approve` steps ask the in-memory ledger for, each covering exactly one later step ([ADR-013](../../docs/adr/ADR-013.md)). Each run starts from a new, empty store and refuses one that already holds data.
