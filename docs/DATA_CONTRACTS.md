# Data contracts, version 1

These are normative application-level contracts, not claims about an existing Apple API schema. Concrete Swift names may evolve before v1 release; persisted and exported identifiers require migration once released.

## Identity and operations

Use distinct wrapper types for `EntityID`, `RequestID`, `SessionID`, `DeviceID`, and `RevisionID`. UUIDs are stable within their declared scope. A device identity is app-generated and revocable, not a hardware serial number or advertising identifier. Names, URLs, and list positions are never primary keys.

An operation request includes `schemaVersion`, `requestID`, `operation`, `actorScope`, optional `expectedRevision`, and a typed payload. The store atomically records the request ID and result with the mutation. Repeating a request returns the original result without replaying effects. A different payload with the same request ID is an error. A stale expected revision produces a conflict proposal, not silent last-writer-wins.

A persisted receipt includes the admitted request, resulting revisions, status, and a bounded inverse when valid. Redacted UI summaries are separate from private debug payloads. User authorization is a short-lived scoped grant checked at commit, not a boolean remembered forever.

A grant (`CommitGrant`, CORE-006) names the adapter that may use it, the operation kinds it covers, and one target: an entity, new items in one collection, or the demo namespace. It expires after 60 seconds by default and 300 at most, on a monotonic clock. Grants live only in memory and are issued by host code when a person acts. They have no decoder or public initializer, so no payload, link, peer message, or model output can create one. `GrantAuthorizationPolicy` requires a live, matching grant for every destructive commit and for every commit through the share extension or from an authorized peer. A commit without one fails closed at the commit, and a replay is checked again. A grant never widens an adapter ceiling (ADR-011), and the ledger refuses to issue one that would.

## Local store and namespaces

The local store is one SQLite file behind the `OperationStore` protocol ([ADR-012](adr/ADR-012.md), proposed). `apply` checks the request ID and every expected revision inside one `BEGIN IMMEDIATE` transaction, then writes the change and its receipt, so the checks and the write hold one lock even across processes. A receipt's status is stored as `{"state":"committed"}` or `{"state":"conflict","conflict":{…}}`, and it lists `removed` entities only when there are any. A stored receipt is never updated or deleted.

The schema version is `PRAGMA user_version`: version 1 has entities, receipts, and `extras`, and version 2 adds namespaces. Migrations are append-only SQL steps, each in its own transaction, and a migration never changes an entity's ID. Every entity row has an `extras` JSON object for metadata this build does not interpret; upserts and migrations never rewrite it. An item's extras (`ItemExtras`, LAB-008-A) are set by its creation (`ItemDraft.extras`), written once when its row is inserted, and carried unchanged by every later revision, including a Reset Demo restore. They are a strict JSON object of at most 64 KiB and 32 levels, and are encoded in a receipt only when present, so receipts without them keep their CORE-002 shape. A file from a newer schema version is refused unchanged.

Every entity is in exactly one namespace. **`user`**: everything a person creates or imports, through any adapter, plus everything stored before namespaces existed. **`demo`**: the synthetic samples from `Fixtures/demo/seed.json`, which only Reset Demo creates. An item has its collection's namespace, no entity changes namespace, and no item can be added to a demo collection. Reset Demo (`resetDemo`, destructive, app UI and App Intents only) makes the demo namespace match the seed. It restores edited or archived samples at their next revision and removes demo entities the seed no longer names. It never changes or removes user data, and the schema itself refuses to delete a user row.

A demo seed file (`format: "native-lab-demo-seed"`, `formatVersion: 1`) is validated whole before anything is written: size at most 1 MiB, known fields only, valid values, unique IDs, and items in listed collections. A rejected file writes nothing, so it cannot block the next valid one. Seed IDs are stable UUIDs. Changing one is a data change that needs a new `seedVersion`.

## Trust Desk credentials

LAB-041-A keeps a desk identity, a sealed record, and a secret apart. The identity is a stable UUID (`DeskIdentityID`). The display name is an item title. Changing the title does not change the identity, the keychain account, or the passkey user handle. The fixture item and its collection live in the user namespace, so Reset Demo does not remove them, and resetting the desk does not touch demo data or any other user item.

The fixture secret is bytes in a generic-password keychain item. The item's service and account are the scope: this desk's service, and the identity's UUID as the account. It is not synchronizable. A receipt, a note, and a `CredentialReference` do not contain those bytes. `CredentialReference.isExportableAppSecret` is false. Copying or exporting a passkey reference is refused.

An `AuthorizationGrant` (LAB-041) is not a `CommitGrant`. It names one purpose, opening the sealed record, and one method, this device or a local confirmation. It expires after 60 seconds by default and 300 at most, on a monotonic clock, and revocation is a flag. Grants live only in memory. They have no decoder or public initializer. A passkey assertion does not issue one. The open itself is still an ordinary `updateItem` receipt through the app UI.

The passkey path is a labeled simulation against the relying party `fixture.trust-desk.invalid`. It is not `ASAuthorizationController`, not an account sign-in, and not an exportable app secret. Private material stays inside the simulator.

## Portable documents

`.anlab` is a UTF-8 JSON metadata document with an app-defined UTType chosen during bundle-identifier configuration. JSON and native document representations preserve the same logical model; a text representation is deliberately lossy and labeled as such. A URL representation is offered only when a meaningful user-approved destination exists.

`.anlabpack` is an optional ZIP package for metadata plus attachments. It contains `manifest.anlab` and attachment files under `assets/`; the manifest uses relative paths, declared byte sizes, and SHA-256 hashes. A bare `.anlab` does not contain external security-scoped bookmarks or assume another device can read an absolute file path.

Illustrative metadata document:

```json
{
  "schemaVersion": 1,
  "documentID": "b609ec72-174e-4a4c-8a27-ef91988970c4",
  "revision": 1,
  "kind": "collection-item",
  "title": "Amber sample",
  "fields": {"category": "original-demo", "note": "User-editable fixture"},
  "provenance": {"origin": "bundled-fixture", "sourceID": "fixture-amber-01"},
  "attachments": [],
  "extras": {}
}
```

Import must preserve unknown non-dangerous fields in `extras`, reject unsupported required versions, and never strip a field silently. Distinguish explicit null, absent, zero, and empty string. Preserve original currency and units; conversion requires an explicit rate/source/date contract. Compare revisions and stable IDs before merging; never overwrite an existing record purely because titles match.

LAB-008-A fixes these details (`LabDocument`, `DocumentMapping`, `ImportPlan`, and `PortableObjectsImporter` in `Packages/LabFeatures/Sources/PortableObjects/`):

- **Format.** A native lab object is a JSON object with `"format": "native-lab-object"` and `"schemaVersion": 1`. `documentID` (a UUID, the item's stable ID), `kind` (`collection-item`), and `title` (a valid item title) are required. `revision` is the exporting store's revision, a whole number of 1 or more. `fields.note` is text, `null`, or absent, and the three stay distinct. `provenance` and `extras` are objects when present. Each attachment is `{"path", "byteCount", "sha256", "mediaType"?}`; its path must pass the same rules as a staged file name (`StagedPath`: no `..`, absolute, lookalike, or invisible components), paths must not collide, and there are at most 32 of them. A higher `schemaVersion` is refused as newer, and another `format` or `kind` is refused.
- **Nothing is dropped.** A document is read into a lossless tree after `StrictJSON` passes. Every member of every object is kept, including fields this build does not know at the top level, in `fields`, `provenance`, an attachment, or `extras`. `null`, `0`, `""`, and `false` stay distinct from absent. A number keeps its literal (`0.0` stays `0.0`). A string keeps its exact Unicode scalars, with no normalization. A top-level field that claims authority or file access (`grant`, `scope`, `actor`, `adapter`, `operation`, `permission`, `bookmark`, and their plurals, in any case) is refused: a document is data only, and naming a refused field in a message would repeat the sender's text.
- **Canonical form.** UTF-8, two-space indentation, the schema's fields in the order `format`, `schemaVersion`, `documentID`, `kind`, `revision`, `title`, `fields`, `provenance`, `attachments`, `extras`, then every other member sorted by the UTF-8 bytes of its key. Only `"`, `\`, and control characters are escaped. The file ends with a line break. Reading and writing a document gives its canonical bytes, and the SHA-256 of those bytes is its content identity.
- **Type.** The uniform type is `<LAB_BUNDLE_PREFIX>.nativelab.object`, declared by each host in `UTExportedTypeDeclarations` (extension `anlab`, conforming to `public.json`) and named in the Info.plist key `LabObjectTypeIdentifier`. Code reads that key and never hard-codes the prefix. Builds with different prefixes on one Mac each claim `.anlab`, and Launch Services types the file with one of them, so every importer also accepts anything that conforms to `public.json`.
- **Representations.** A drag, share, or export offers, in order: the native document as a file and as data, JSON (the same bytes), and plain text. The plain text is a labeled summary that says what it leaves out. No URL is offered, because this build has no destination a person approved.
- **The item and the document.** The document's `documentID` is the item ID. The item holds the title and note. Everything else goes into the item's extras as one versioned entry: `{"portableObject": {"version": 1, "note": "text" | "null" | "absent", "document": {…}}}`. Here `document` is the document without `format`, `schemaVersion`, `documentID`, `revision`, `title`, and `fields.note`, and `note` records the note's form. Exporting the item rebuilds the document from that entry, with the item's current title, note, and revision. An imported object starts at revision 1 in its new store, so export, import into another lab, and export again give the same bytes when the source was at revision 1, and differ only in `revision` otherwise. A title with surrounding spaces is trimmed, and the review says so.
- **Importing.** Every import is staged first under the fixed name `object.anlab`, never the sender's file name. Staging applies the 2 MiB and `StrictJSON` limits while the bytes stream. The staged bytes are read back and checked, decoded with every rule above, and planned against the lab by identity. An object the lab does not hold is created in a collection of the person's own. One it holds with the same title and note needs nothing, so a reimport never duplicates it. One it holds with a different title or note is changed only if the person applies the document's title and note: one `updateItem` at the stored revision, whose receipt offers an undo, and extras stay as stored. An archived stored copy is not changed. A document that lists attachments is refused, because this build has no attachment entity and would leave them behind. At commit, the staged bytes are verified again, their digest must equal the reviewed one, and the plan must still be the reviewed decision. The request ID derives from the digest and the target, so a retry replays its receipt. Imports commit through `OperationService` as the app UI after a person's press. That is a non-destructive app-UI commit, so ADR-013 issues no grant for it.

### Speech timelines (LAB-013)

LAB-013-A adds two exports and one saved form, all built from finalized segments only; provisional text is never written (`TimelineExport`, `CaptionDocument`, and `TranscriptSave` in `Packages/LabFeatures/Sources/SpeechTimeline/`):

- **Timeline export.** A JSON object with `"format": "native-lab-speech-timeline"`, `"schemaVersion": 1`, `language` (BCP 47, the transcript's language, never a speaker), `audio`, and `segments`. Keys are sorted and there is no extra whitespace, so the same timeline gives the same bytes. Reading one back refuses an unknown top-level field, another version, overlapping segments, text over 500 characters or with control characters, and word times outside their segment.
- **Segments.** Each has `id` (its number in the timeline), `range` as whole milliseconds (`startMs`, `endMs`, end exclusive), the current `text`, the `recognized` text the source gave, `source` (`on-device-transcriber`, `caption-import`, or `manual`), and optional `words` with their own ranges. A correction changes `text` only; `range`, `recognized`, and `words` stay.
- **Audio reference.** `origin` (`synthesized-sample`, `imported-file`, `recording`, or `none`), the SHA-256 of the audio file's bytes, its duration, and its file type. Never its name or path, and never the audio. A recording keeps no audio, so it has no hash.
- **Captions.** WebVTT with one cue per segment, its number as the cue identifier, and `&`, `<`, and `>` escaped. The reader takes cue identifiers and settings, skips `NOTE`, `STYLE`, and `REGION` blocks, removes markup such as voice tags, and refuses a whole file for overlapping cues, a malformed timestamp, or more than 256 KB.
- **Saving.** One `createItem` in a collection of the person's own, committed as the app UI: the title names the source, the note holds the segments' text (shortened to the note limit, with an ellipsis), and the item's extras hold the whole timeline export under `speechTimeline`. A timeline too large for the 64 KB extras is refused before anything is sent.

## Continuation hints

LAB-016-A. A continuation is a hint, not a copy of the draft and not a sync (ADR-006). Handoff and the continuation link carry three fields and nothing else: `documentID` (the item's UUID), `revision` (a whole number of 1 or more, the revision the sender had seen), and `section` (a zero-based index into the note split on a blank line). A payload or link with any other field is refused, and the refusal does not repeat the sender's text. The activity title is the fixed string "Pick Up Here". Search indexing, public indexing, a web URL, and continuation streams stay off.

The explicit document is a separate copy a person makes. It is UTF-8 JSON, `"format": "native-lab-continuation"`, `"schemaVersion": 1`, with `documentID`, `revision`, `title`, and `sections` in that order and no other keys. A section may not itself contain a blank line, so joining on `\n\n` and splitting again agree. The canonical bytes end with a line break. Importing one creates the item through `OperationService` when the lab does not already hold that ID, and leaves an existing item unchanged. The destination clamps a section index into the draft it actually holds.

## Durable sync ledger

LAB-017-A fixes the manual-exchange document (`LedgerDocument` in `Packages/LabFeatures/Sources/DurableSyncLedger/`):

- **Format.** UTF-8 JSON, `"kind": "native-lab-sync-ledger"`, `"schemaVersion": 1`. `account` is a UUID. `scope` is `private` or `shared`. A shared document names `share`; a private document does not. `envelopes` is the mutation log. Unknown fields, duplicate keys, a `public` scope, and a higher schema version are refused before any envelope is appended. The file is at most 2 MiB and at most 4,096 envelopes.
- **Accounts.** A private document is applied only by the account it names. A shared document is one share, and the file profile admits members explicitly. Neither document is a public database.
- **Merge.** Each envelope carries a version vector. An edit that happened after another wins. Edits that were made apart stay as a conflict until a person chooses. The choice is a new envelope. A tombstone that dominates an older edit does not recreate the record.
- **Where it is written.** Each device appends its own write-ahead log, then materializes through `OperationService`. The optional profile is a directory of one JSON file per mutation. Reset Demo for this experiment removes only that experiment's folder.

## Import resource policy

Initial defaults: at most 32 attachments per import; at most 2 MiB of metadata/text; at most 1 GiB total staged media; at most 2,000 archive entries; nesting depth at most 16. These are proposed protective defaults, not measured device limits. Media should stream to disk rather than allocate the declared total in memory. A smaller device/profile can impose stricter limits, and the UI must show the effective limit before import.

Reject absolute paths, `..` traversal, symlink/hardlink escape, overlapping destination names, checksum mismatch, malicious compression expansion, and unsupported media. Apply decompressed-size limits while streaming, not only to archive headers. Quarantine failed imports and provide removal; they cannot prevent later valid imports. Treat all text as data, including strings that look like agent instructions.

CORE-006 fixes these details (`ImportLimits`, `StagedPath`, `ArchivePolicy`, and `StrictJSON` in `Packages/LabDomain/Sources/LabDomain/Staging/`; the ZIP reader in `Packages/LabStaging`):

- **Counts.** The 32-file limit applies to files after an archive expands. The 2,000-entry limit, which counts folders too, is checked on the archive's directory before anything expands.
- **Names.** A file or entry name is validated from its raw bytes. It must be strict UTF-8, which rules out overlong forms such as `C0 AF` for `/`. It must not be absolute or a drive path, and must not contain a `.` or `..` component, an empty component, a backslash, NUL, or a control character. It must not contain a character that is, or normalizes under NFKC to, a separator or `.`/`..`: fullwidth or division slashes, the colon, fullwidth full stops, a two-dot leader. Bidirectional controls and invisible characters are refused. The limits are 1,024 bytes per path, 255 per component, and 16 components. Names that differ only in case or Unicode normalization collide, and so do a file and a folder with the same name. Staged bytes are stored under their position, never under their name.
- **Archives.** Only ZIP with stored or deflated entries is expanded. Encryption, ZIP64, multiple disks, other methods, bytes before or between entries, link and special entries, and entries whose bytes overlap are refused. So is an entry whose name or first bytes mark another archive. An entry larger than 1 MiB may not expand more than 100 times its compressed size, and neither may the archive as a whole. Each entry stops at its declared size while it streams, and its CRC-32 must match.
- **Text and JSON.** Shared text is at most 2 MiB of strict UTF-8. The only control characters it may contain are line breaks and tabs. A JSON file (`.json`, `.anlab`) must pass `StrictJSON` before any decoder sees it. `StrictJSON` refuses duplicate keys, including keys that are equal after unescaping or under canonical equivalence. It also refuses unpaired surrogate escapes and nesting deeper than 16. A shared link must be `http` or `https`, at most 2,000 bytes, with no user name or password. A page title is at most 1,024 bytes.
- **Staging record.** A staging record (`format: "native-lab-staging-record"`, `formatVersion: 1`) holds only a digest, a time, and a payload: text, a link and its title, or a list of files with each file's name, size, and SHA-256. Its ID derives from the digest, so staging the same content twice is a duplicate. The app decodes it again from bytes. Decoding refuses any field the format does not define, including a smuggled scope, grant, or operation. Adoption turns a record into exactly one new item in the collection the person chose. Text adopts only when it fits an item note (2,000 characters), and files wait for an attachment entity.

## Desktop notes

A desktop note (LAB-042-A) is an ordinary lab item in the user collection Desktop Notes (`04200000-0000-4000-8000-000000000042`). Its title and body are the item title and note. Its extras hold `{"desktop":{"origin":"file-import"|"selected-text"|"script","privacy":"ordinary"|"private"}}`. A fixture preview is not an item and is not written. The item ID is a name-based UUID of the origin, privacy, and text, so the same text from a second entry point joins the existing item. The request ID also includes the adapter, so each entry point retries its own request. Scene storage keeps ordinary document IDs only, never a title or body, and a restore skips a private ID even when a snapshot names it. Import commits `createItem` through `OperationService`. The menu uses the app UI actor. The intent uses the App Intent actor. A model tool is refused and writes nothing. Shell text is refused before any commit. Selected text that looks like a shell is stored as a note.

## Jobs and progress

A job has `jobID`, kind, source revision, state, checkpoint version, completed work units, optional total units, and cancellation ownership. States are queued, running, waiting-for-resource, completed, cancelled, or failed. A missing total means indeterminate progress. Reopening a Live Activity cannot restart a terminal job. Export adoption is atomic: temporary output is not the final file until validated.

## Live session envelope

A protocol-v1 envelope contains `protocolVersion`, `sessionID`, `sessionEpoch`, `messageID`, `senderPeerID`, `role`, `sequence`, `kind`, optional `baseRevision`, and bounded typed payload. Never admit arbitrary code, method names, file paths, or shell strings. Role authorization is checked on the receiver. Schema mismatch is a explained refusal.

Monotonic clocks are device-local and cannot be compared directly. A clock estimate uses multiple round trips and records offset, uncertainty, and calibration age. A peer reboot creates a new epoch; previous samples are invalid. Durability timestamps may use UTC, but media alignment uses a declared presentation timebase. Acknowledgement stages distinguish locally queued, transport-received, admitted, and applied.

Reliable commands and replaceable samples are separate queues. A replayed message ID returns its previous admission result. Stale replaceable samples are dropped. When sequence continuity is lost or a peer reconnects, acquire a snapshot before admitting mutations. Bounded queues and expiration prevent a stale wrist input from unexpectedly changing a later session.

## Evidence records

An evidence record names experiment/ticket ID, commit/revision, build/toolchain, SDK/OS, device class, input fixture hash, adapter path, consent state, exact steps, expected/observed results, measurements with units, and limitations. Never fabricate an identifier when no run occurred. Store explicit `not-run` rather than an empty success value.
