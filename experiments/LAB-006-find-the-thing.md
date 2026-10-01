---
id: "LAB-006"
title: "Find the Thing"
state: "implemented"
milestone: "M2"
category: "Intelligence"
depends_on: ["LAB-001", "LAB-010"]
source_review: "2026-09-29"
---

# LAB-006 — Find the Thing

## The moment

Search a deliberately messy local collection and see exactly which owned records informed the answer.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac.

**Primary APIs:** Core Spotlight, AppEntity indexing, optional model retrieval. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** SearchDocument, SearchHit, EvidencePointer. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Index only opted-in lab records
2. Return stable IDs and deep links
3. Offer lexical search before optional semantic retrieval
4. Delete and reindex with auditable counts

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Deleted private data is removed from the app index.
- [ ] An unsupported query returns no invented results.
- [ ] A generated answer cites actual record IDs.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

No assumption of global Spotlight access to other apps or the entire Mac.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Lexical in-app search with the same result model.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/find-the-thing/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-006-A):

- `Packages/LabFeatures/Sources/FindTheThing/`: `SearchDocument`, `SearchHit`, `EvidencePointer`, `SearchAnswer`, `AppSearchIndex` (opted-in records only), `FindTheThingOperation` (lexical search before optional semantic retrieval, delete/reindex with audit counts, donation), `ServiceFindBackend` (archives lab items through `OperationService`), `MessyCollection` fixtures, and `FindRecordEntity` / `IndexedEntityDonor` on iOS and macOS only. It depends on LabDomain and never holds the store.
- `Apps/Shared/FindTheThing/`: the shared session over one app index, the page, and `FindTheThingHost.connect()` for entity-query dependency injection. The Mac reaches it from the sidebar and View › Find the Thing (⌥⌘7), with columns in `Apps/Mac/Window/FindTheThingColumns.swift`. The iPhone reaches it from this experiment's catalog page.
- No Watch or Apple TV surface: `IndexedEntity` and `CSSearchableIndex.indexAppEntities` are unavailable there; those hosts keep the idle donor and in-app lexical search is not linked.

## Implementation notes (LAB-006-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs. These are package and host compile facts, not device proof.

- `IndexedEntity` and `CSSearchableIndex.indexAppEntities` / `deleteAppEntities(identifiedBy:ofType:)` are macOS 15.0, iOS 18.0, visionOS 2.0. They do not appear in the watchOS or tvOS App Intents interfaces. No entitlement is required for donating this app's own indexed entities.
- Donation is an explicit Index action. Opening the experiment only loads the shelf into the empty in-app index; it does not call Spotlight.
- Semantic retrieval is optional and off by default (`UnavailableSemanticRetriever`). Lexical search always runs first; a retriever's IDs are kept only when the app index holds them.
- The deep link `nativelab://find/<uuid>` is an in-app name. This build does not register a system URL type and does not search other apps' indexes.

## Delivery

[Implementation ticket](../tickets/LAB-006-A.md) → [qualification ticket](../tickets/LAB-006-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-010](LAB-010-typed-local-intelligence.md).

**Primary-source references:** [S02](../docs/SOURCE_INDEX.md#s02), [S06](../docs/SOURCE_INDEX.md#s06). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
