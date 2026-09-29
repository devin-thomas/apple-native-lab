---
id: "CORE-006"
title: "Enforce import, authorization, logging, and export safety"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-002", "CORE-003"]
---

# CORE-006 — Enforce import, authorization, logging, and export safety

## Goal

Make the trust boundaries real before shared text, media, and generated proposals enter the system.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Domain validation, staging service, diagnostic/export policy tests.

## Implementation steps

1. Implement staged import size/path/hash limits and cancellation
2. Add scoped short-lived authorization grants at commit
3. Provide metadata-only diagnostics and selected redacted export
4. Write hostile-input and unauthorized-operation test fixtures

## Acceptance criteria

- [x] A path traversal/archive expansion attempt is rejected before adoption. (22 hostile names, as shared file names and as archive entries, and 27 other archive attacks built in tests, each refused before anything is written to `pending/`.)
- [x] Imported instruction text cannot expand tool permissions. (Instructions, a forged scope or grant, a real grant's ID, and a model tool acting on the text: each commits nothing beyond one new item, and no grant appears.)
- [x] No default log contains raw prompts, filenames, tokens, or personal content. (Sentinel material in every field; the events, sink output, export, error text, quarantine reason files, and the macOS system log hold none of it.)
- [x] A cancelled import leaves no final adopted object. (Cancelled while streaming, before staging, before expansion, and between validation and commit: no staged record and no item.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:**

- New in `Packages/LabDomain/Sources/LabDomain/`, the policy folders recorded for this ticket:
  - `Staging/`: import limits, path, UTF-8, and JSON validation, archive policy, the staging record, the inbox protocol, and the adopter.
  - `Grants/`: commit grants, the ledger, and the grant policy.
  - `Diagnostics/`: the logging and diagnostics facade, the system log sink, and the export.
- Nine new test files in `Packages/LabDomain/Tests/LabDomainTests/`. No existing LabDomain file changed.
- New package `Packages/LabStaging`, with library `LabStaging` and tests `LabStagingTests`.
- New `Fixtures/hostile/`: seven fixtures and a README.
- `docs/DATA_CONTRACTS.md`: grant and import-policy details.
- `docs/SECURITY_AND_PRIVACY.md`: a new section, "How CORE-006 enforces this".
- Evidence rows in `docs/BUILD_STATUS.md` and this record.

No app target, project, config, script, or workflow changed, and no host uses the new code yet.

**Why a new package:** `LabStaging` holds the file-system side of staging. That covers the staging folder, link-safe opening, exclusive renames, data protection attributes, and streaming ZIP expansion through the `Compression` framework. File I/O stays out of the pure domain core, as SQLite does in LabStore, and a share extension can link LabDomain and LabStaging without the store. It depends only on LabDomain and system frameworks.

**Policy API:**

- **Staging.**
  - `ImportLimits` holds the documented defaults. Every value can only be narrowed.
  - `StagedPath` validates a name from its raw bytes, and `StagedPathSet` detects names that collide.
  - `StrictUTF8`, `StrictJSON`, and `ArchivePolicy` check content before anything decodes or expands it.
  - `StagingRecord` is a digest-identified record: text, a link, or files. It decodes strictly and refuses unknown fields.
  - `StagingInbox` is the inbox protocol. `InMemoryStagingInbox` is its reference implementation, and `StagingArea` in LabStaging stores it on disk.
  - `ImportAdopter` adopts one record as one new item through `OperationService`.
  - `ImportRejection` holds every refusal. Each case has a `userMessage`, a content-free `code`, and a `category`.
- **Grants.**
  - `CommitGrant` names an adapter, operation kinds, a `GrantTarget`, and an expiry.
  - `GrantLedger` issues, revokes, and checks grants on an injectable `GrantClock`. Grants last 60 seconds by default and 300 at most.
  - `GrantAuthorizationPolicy` requires a grant under `GrantRequirement.sensitiveCommits`: every destructive commit, and every commit through the share extension or from an authorized peer.
- **Diagnostics.**
  - `DiagnosticsLog` is the only logging entry point. It has `record` and `measure`, keeps the last 500 events, and can purge them.
  - A `DiagnosticEvent` holds only literal names, validated IDs, enums, numbers, and a time.
  - Sinks: `OSLogDiagnosticSink` and `CollectingDiagnosticSink`.
  - `exportPreview(_:)` returns a `DiagnosticExportPreview` whose `text` is exactly the file that `write(to:)` saves.

**Acceptance evidence** (fixture path, macOS; see BUILD_STATUS):

- **Traversal and expansion:**
  - `StagingPolicyTests`, `ArchiveTests`, `StagingAreaTests`, `HostileFixtureTests`, and `BoundedExpansionTests` cover every case in `traversal-names.json`. Names that are valid text are tried as shared file names, and are refused before any byte is read. Every name is also tried as a ZIP entry.
  - Archive attacks refused before anything is written: a 32 MiB zip bomb (by ratio); a bomb spread over 24 entries; an entry that lies about its size, stopped at its declared size by the inflater and again by the writer; the total expanded size; 2,001 entries; 33 files; nested archives by name and by signature; overlapping entries; symbolic link and special entries; encryption; ZIP64; multiple disks; an unknown method; extra data; a bad CRC; a mismatched local header; truncation; and colliding names.
  - `TamperTests` shows the app refuses and quarantines each of these, and that the next import still works: symbolic and hard links, a linked folder or record, extra and missing files, changed bytes, a changed record, and the forged record.
- **Instructions:** `InstructionInjectionTests` and `HostileFixtureTests.promptInjectionStaysData`.
  - The injection fixture becomes exactly one note. The receipt has one change, and every other entity is unchanged.
  - The only live grant is the one the person gave. The share extension still cannot archive, and the ledger will not grant it.
  - A forged record with a scope, grant, and operation is refused as `unknownRecordField`.
  - A real grant's ID pasted into text authorizes nothing (`grantOutOfScope`).
  - A model tool reading the imported text can propose but not commit.
  - `CommitGrant`, `ActorScope`, `OperationRequest`, and `DiagnosticEvent` have no decoder.
- **Logs:** both `DiagnosticsPrivacyTests` suites put sentinel file names, tokens, prompts, content, hosts, and paths into every field a person controls, through staging, rejection, quarantine, grants, and adoption. None appears in any event line, sink, export, error text, or quarantine reason file. None appears in the entries `OSLogStore` returns for the process, either. `LoggingDisciplineTests` fails on any direct `print`, `NSLog`, `os_log`, `Logger`, or standard-stream call in `Apps/` or package sources outside `Diagnostics/`.
- **Cancellation:**
  - `StagingAreaTests.aCancelledImportLeavesNothingBehind` cancels a stalled, cloud-like stream mid-file. It checks that `incoming/` and `pending/` are empty, and that the next import works.
  - Pre-cancelled staging and expansion stage nothing.
  - `ImportAdoptionTests.aCancelledImportLeavesNoAdoptedObject` cancels between validation and commit. No commit happens, the record stays waiting, and a later adoption succeeds.
- **Grants:** `GrantTests` covers these cases, each failing closed at commit: a missing grant; an expired grant; a grant for another target, operation, or adapter; a revoked grant; a clock reading before issue; and a replay after expiry. `anApprovalThatLapsesBeforeTheCommitFailsAtTheCommit` shows the policy inside `perform` refuses even after the adopter's own check passed. The ledger refuses to issue beyond a ceiling, and the service still applies the ceiling before any grant.
- **Duplicates:** the same content has one staging ID and is refused by an exclusive rename. Adoption derives the request and item IDs from the digest and the collection, so a second adoption returns the original receipt and stores nothing.

**Not run:**

- A real share extension, `NSItemProvider`, or App Group container. No extension target exists yet (LAB-007-A), and App Groups need a paid team.
- `completeUnlessOpen` data protection. It is set on iOS, watchOS, and tvOS, but not enforced on macOS or in the simulator, so no device proof exists.
- Cross-process staging with two live processes. Durability is shown with two `StagingArea` instances on one folder.
- Any physical device.

**Specification notes:**

- ARCHITECTURE puts metadata-only diagnostics in LabSupport. The facade is in LabDomain instead, so the domain, the stores, and the adapters can all use it without LabSupport's platform frameworks.
- LAB-007 proposes `ImportEnvelope` and `StagedAttachment`. `StagingRecord` and `StagedFile` fill those roles.
- Files are validated and kept in staging, but not adopted: the domain has no attachment entity yet (LAB-008).
- The 32-file limit applies after expansion; the 2,000-entry limit applies to the archive directory first.
- The compression ratio limit (100:1 above 1 MiB) is a new proposed default.
