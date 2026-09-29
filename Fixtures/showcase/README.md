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
