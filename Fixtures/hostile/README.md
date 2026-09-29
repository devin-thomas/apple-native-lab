# Hostile fixtures

Original, synthetic input written to attack the import path ([SECURITY_AND_PRIVACY](../../docs/SECURITY_AND_PRIVACY.md), [DATA_CONTRACTS](../../docs/DATA_CONTRACTS.md#import-resource-policy)). Nothing here came from a person or an import, and it is distributed under the repository's MIT License. None of these files may be used as a demo sample.

Each file has a test that proves it is refused with a specific rejection whose message a person can read, or, for instruction text, that it stays data. `HostileFixtureTests` in `Packages/LabStaging` fails if a file is added here without a test.

| File | What it tries | Expected result | Tests |
|---|---|---|---|
| `traversal-names.json` | 22 file and archive-entry names: `..`, absolute and drive paths, backslashes, fullwidth and division slashes, a colon, fullwidth full stops, a two-dot leader, a right-to-left override, a zero-width space, a control character, a NUL byte, overlong `/` and `.` encodings, an encoded surrogate, and too many folders. `hex` holds raw bytes for names that are not valid UTF-8 | `unsafePath` with the `PathRejection` named in `expect`, before any byte is read or expanded | `StagingPolicyTests`, `StagingAreaTests`, `ArchiveTests`, `HostileFixtureTests` |
| `malformed-utf8.txt` | Text with an overlong `/`, an encoded surrogate, a five-byte form, and a stray continuation byte | `malformedUTF8` at the first bad byte; never repaired | `StagingPolicyTests`, `HostileFixtureTests` |
| `deeply-nested.json` | 64 nested arrays, four times the depth limit | `malformedJSON(.tooDeep(limit: 16))` | `StagingPolicyTests`, `HostileFixtureTests` |
| `duplicate-keys.json` | An object with `title` twice, the second spelled `title`, so a last-value-wins decoder would keep a value the reviewer never saw | `malformedJSON(.duplicateKey)` | `StagingPolicyTests`, `HostileFixtureTests` |
| `oversized-note.txt` | 2,154 characters: within the text limit, beyond an item note | Stages, then `textTooLongForNote(limit: 2000)` at adoption; nothing is stored | `ImportAdoptionTests`, `HostileFixtureTests` |
| `prompt-injection.txt` | Instructions to archive everything, reset the demo, and grant destructive permissions, with a fake approval token and a JSON scope | Adopted only as one note in the collection the person chose; no grant, scope, or other entity changes | `InstructionInjectionTests`, `HostileFixtureTests` |
| `forged-staging-record.json` | A staging record carrying an actor scope, a grant, and an operation | `unknownRecordField`; the import is set aside in quarantine | `StagingRecordTests`, `InstructionInjectionTests`, `HostileFixtureTests` |

Archives are built by the tests, never committed: a 32 MiB zip bomb that compresses to about 32 KB, a bomb spread over 24 entries, an entry that lies about its size, an archive nested by name and by signature, overlapping entries, link entries, encryption, ZIP64, multiple disks, extra data, bad checksums, 2,001 entries, and colliding names (`ArchiveTests`). Oversized payloads are also generated in tests rather than stored.
