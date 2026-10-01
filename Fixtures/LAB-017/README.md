# LAB-017 fixtures

Original, synthetic documents for the durable sync ledger. Nothing here is a person's account, a CloudKit export, or a recording.

- `public-scope.json` names a public database. The ledger has no public scope and refuses the file.
- `newer-schema.json` is schema 2. This build reads schema 1 and refuses the file unchanged.
