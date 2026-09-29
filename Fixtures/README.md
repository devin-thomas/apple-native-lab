# Fixtures

Original, public-safe data that the lab loads or tests against. Everything here is synthetic and written for this project, and it is distributed under the repository's MIT License. Nothing here is a person's real data, and nothing here came from an import ([ASSET_POLICY](../docs/ASSET_POLICY.md)).

## Namespaces

Every stored collection and item is in one of two namespaces ([DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#local-store-and-namespaces)).

| Namespace | What is in it | Reset Demo |
|---|---|---|
| `demo` | The samples in `demo/seed.json`, including a person's later edits to them | Restores every sample to the seed and removes demo entities the seed no longer lists |
| `user` | Everything a person creates or imports, through any adapter | Never changed or removed |

Only Reset Demo creates demo entities. A person cannot add an item to a demo collection, so nothing a person creates can end up in the demo. Edits to a sample stay part of the demo, and a reset reverts them.

## `demo/seed.json`

The demo seed has 3 collections and 12 items (LAB-001's 12 original sample objects). The store loads it as data through `DemoFixture` and commits it with `DomainOperation.resetDemo(seed:)`, which also seeds the first run.

- The UUIDs are stable and were generated once at random. Never change or reuse one: a sample's identity is what lets Reset Demo restore it instead of adding a copy. `ResetDemoTests` pins every ID.
- To add a sample, give it a new UUID. To change content, also raise `seedVersion`.
- The format is strict. An unknown field, a blank or overlong title, a control character, a duplicate ID, or an item in an unlisted collection rejects the whole file, and nothing is written.
- A host bundles this file as a resource; the package does not embed a copy.

## Per-experiment fixtures

Each experiment's own fixtures belong to that experiment's lead, under `Fixtures/<LAB-ID>/`. They follow the same rules: original, synthetic, stable IDs, and no private or imported content.

Replayable showcase scripts and their seeds live in [`showcase/`](showcase/README.md); `Packages/LabDemo` runs them.
