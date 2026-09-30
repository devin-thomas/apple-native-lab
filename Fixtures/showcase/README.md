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

## Script format

`script.json` (`format: "native-lab-demo-script"`, `formatVersion: 1`) names its seed, a file in the same folder in the demo seed format that `Fixtures/demo/seed.json` uses. `DemoScript(folder:)` loads both:

- **Reading.** Each file must be an ordinary, visible, singly linked file inside the folder, reached without a symbolic link.
- **Parsing.** Each must be strict JSON with no duplicate keys, and every field must be one the format defines.
- **Steps.** Each step has an `id` and exactly one action:
  - `approve`: the name of a later step.
  - `find`: optional `collection`, `text`, `includeArchived`, and `limit`, and the ordered item IDs it must `expect`.
  - A change, with a `request` UUID: `resetDemo`, one of the domain operations such as `updateItem` or `archiveItem`, or `undo`, which names an earlier step.
- **Order.** The first change must be `resetDemo`, with the script's own seed.

A script cannot choose its adapter, permissions, or grants. The runner acts as the app UI with that adapter's fixed ceiling ([ADR-011](../../docs/adr/ADR-011.md)). Its only grants are the ones its `approve` steps ask the in-memory ledger for, each covering exactly one later step ([ADR-013](../../docs/adr/ADR-013.md)). Each run starts from a new, empty store and refuses one that already holds data.
