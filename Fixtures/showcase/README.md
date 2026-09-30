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
