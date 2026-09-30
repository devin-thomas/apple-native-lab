# LAB-008 Portable Objects fixtures

Original, synthetic lab documents (`.anlab`, [DATA_CONTRACTS](../../docs/DATA_CONTRACTS.md#portable-documents)) written for this project and distributed under the repository's MIT License. Nothing here came from a person or an import.

The valid sample lives with its module, because the app bundles it for **Import Sample Object**: [`Packages/LabFeatures/Sources/PortableObjects/Resources/sample-object.anlab`](../../Packages/LabFeatures/Sources/PortableObjects/Resources/sample-object.anlab). It is already in canonical form, with a stable ID (`F1586771-0F15-4044-A372-5F9BC9968FDB`), a title with a combining accent (e + U+0300), CJK, and an emoji, an empty note, `null`, `0`, `0.0`, `""`, and `false` values, a field this build does not know at the top level and inside `fields`, and extras. `DocumentCodecTests.theBundledSampleIsAlreadyCanonical` pins its bytes.

The files here are hostile. Each is refused with a sentence a person can read, and nothing is staged or stored (`ImportTests.hostileFixturesAreRefusedWithAReadableReason`, `ImportTests.aTraversalAttachmentIsRefusedAndLeavesNothingInStaging`).

| File | What it tries | Expected result |
|---|---|---|
| `traversal-attachment.anlab` | An attachment path that climbs out with `..` | `unsafeAttachmentPath(position: 1, .parentReference)` |
| `newer-schema.anlab` | `schemaVersion` 2 | `newerSchema(found: 2, supported: 1)` |
| `authority-field.anlab` | A top-level `grant` and `scope` | `authorityField`; a document is data only |
| `duplicate-keys.anlab` | `title` twice, the second spelled `title` | Staging refuses it as strict JSON (`duplicate-key`) |
| `malformed.anlab` | A document cut off mid-string | Staging refuses it as strict JSON (`invalid-syntax`) |

An oversized document (over 2 MiB) is generated in the tests rather than stored.
