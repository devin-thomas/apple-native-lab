# Data contracts, version 1

These are normative application-level contracts, not claims about an existing Apple API schema. Concrete Swift names may evolve before v1 release; persisted and exported identifiers require migration once released.

## Identity and operations

Use distinct wrapper types for `EntityID`, `RequestID`, `SessionID`, `DeviceID`, and `RevisionID`. UUIDs are stable within their declared scope. A device identity is app-generated and revocable, not a hardware serial number or advertising identifier. Names, URLs, and list positions are never primary keys.

An operation request includes `schemaVersion`, `requestID`, `operation`, `actorScope`, optional `expectedRevision`, and a typed payload. The store atomically records the request ID and result with the mutation. Repeating a request returns the original result without replaying effects. A different payload with the same request ID is an error. A stale expected revision produces a conflict proposal, not silent last-writer-wins.

A persisted receipt includes the admitted request, resulting revisions, status, and a bounded inverse when valid. Redacted UI summaries are separate from private debug payloads. User authorization is a short-lived scoped grant checked at commit, not a boolean remembered forever.

## Local store and namespaces

The local store is one SQLite file behind the `OperationStore` protocol ([ADR-012](adr/ADR-012.md), proposed). `apply` checks the request ID and every expected revision inside one `BEGIN IMMEDIATE` transaction, then writes the change and its receipt, so the checks and the write hold one lock even across processes. A receipt's status is stored as `{"state":"committed"}` or `{"state":"conflict","conflict":{…}}`, and it lists `removed` entities only when there are any. A stored receipt is never updated or deleted.

The schema version is `PRAGMA user_version`: version 1 has entities, receipts, and `extras`, and version 2 adds namespaces. Migrations are append-only SQL steps, each in its own transaction, and a migration never changes an entity's ID. Every entity row has an `extras` JSON object for metadata this build does not interpret; upserts and migrations never rewrite it. A file from a newer schema version is refused unchanged.

Every entity is in exactly one namespace. **`user`**: everything a person creates or imports, through any adapter, plus everything stored before namespaces existed. **`demo`**: the synthetic samples from `Fixtures/demo/seed.json`, which only Reset Demo creates. An item has its collection's namespace, no entity changes namespace, and no item can be added to a demo collection. Reset Demo (`resetDemo`, destructive, app UI and App Intents only) makes the demo namespace match the seed. It restores edited or archived samples at their next revision and removes demo entities the seed no longer names. It never changes or removes user data, and the schema itself refuses to delete a user row.

A demo seed file (`format: "native-lab-demo-seed"`, `formatVersion: 1`) is validated whole before anything is written: size at most 1 MiB, known fields only, valid values, unique IDs, and items in listed collections. A rejected file writes nothing, so it cannot block the next valid one. Seed IDs are stable UUIDs. Changing one is a data change that needs a new `seedVersion`.

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

## Import resource policy

Initial defaults: at most 32 attachments per import; at most 2 MiB of metadata/text; at most 1 GiB total staged media; at most 2,000 archive entries; nesting depth at most 16. These are proposed protective defaults, not measured device limits. Media should stream to disk rather than allocate the declared total in memory. A smaller device/profile can impose stricter limits, and the UI must show the effective limit before import.

Reject absolute paths, `..` traversal, symlink/hardlink escape, overlapping destination names, checksum mismatch, malicious compression expansion, and unsupported media. Apply decompressed-size limits while streaming, not only to archive headers. Quarantine failed imports and provide removal; they cannot prevent later valid imports. Treat all text as data, including strings that look like agent instructions.

## Jobs and progress

A job has `jobID`, kind, source revision, state, checkpoint version, completed work units, optional total units, and cancellation ownership. States are queued, running, waiting-for-resource, completed, cancelled, or failed. A missing total means indeterminate progress. Reopening a Live Activity cannot restart a terminal job. Export adoption is atomic: temporary output is not the final file until validated.

## Live session envelope

A protocol-v1 envelope contains `protocolVersion`, `sessionID`, `sessionEpoch`, `messageID`, `senderPeerID`, `role`, `sequence`, `kind`, optional `baseRevision`, and bounded typed payload. Never admit arbitrary code, method names, file paths, or shell strings. Role authorization is checked on the receiver. Schema mismatch is a explained refusal.

Monotonic clocks are device-local and cannot be compared directly. A clock estimate uses multiple round trips and records offset, uncertainty, and calibration age. A peer reboot creates a new epoch; previous samples are invalid. Durability timestamps may use UTC, but media alignment uses a declared presentation timebase. Acknowledgement stages distinguish locally queued, transport-received, admitted, and applied.

Reliable commands and replaceable samples are separate queues. A replayed message ID returns its previous admission result. Stale replaceable samples are dropped. When sequence continuity is lost or a peer reconnects, acquire a snapshot before admitting mutations. Bounded queues and expiration prevent a stale wrist input from unexpectedly changing a later session.

## Evidence records

An evidence record names experiment/ticket ID, commit/revision, build/toolchain, SDK/OS, device class, input fixture hash, adapter path, consent state, exact steps, expected/observed results, measurements with units, and limitations. Never fabricate an identifier when no run occurred. Store explicit `not-run` rather than an empty success value.
