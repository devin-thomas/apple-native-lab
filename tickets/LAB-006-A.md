---
id: "LAB-006-A"
title: "Implement Find the Thing"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-010-B"]
---

# LAB-006-A — Implement Find the Thing

## Goal

Search a deliberately messy local collection and see exactly which owned records informed the answer.

## Authority and scope

Read the [governing specification](../experiments/LAB-006-find-the-thing.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** find-the-thing module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Index only opted-in lab records
3. Return stable IDs and deep links
4. Offer lexical search before optional semantic retrieval
5. Delete and reindex with auditable counts
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Deleted private data is removed from the app index. (`deletingThePrivateNoteRemovesItFromTheIndex`: after delete, `birchbark` returns no hits and no citations. `reindexKeepsADeletedFixtureOutUntilReset` keeps it out until Reset Fixtures. `archivingALabItemRemovesItFromTheIndexAndKeepsTheReceipt` archives through `OperationService` and drops the index entry.)
- [x] An unsupported query returns no invented results. (`anUnsupportedQueryInventsNothing` for empty, overlong, control-character, and non-word queries; each refusal says "Nothing was invented." `anUnlistedRecordIsNotAHit` for the not-opted-in packing slip. A semantic retriever that invents every ID returns an empty answer with no invented IDs.)
- [x] A generated answer cites actual record IDs. (`cedarSearchCitesTheTwoRecordsInAStableOrder`: prose and citations name the two cedar record UUIDs and deep links, never the cobalt ID. Semantic path keeps only IDs the index holds.)
- [x] Fallback is usable: Lexical in-app search with the same result model.. (`withoutARetrieverTheSameHitModelIsLexical`; default `UnavailableSemanticRetriever`. UI Search uses the same `SearchAnswer` / `EvidencePointer` shape.)
- [x] Sensitive operations share the domain authorization/receipt path. (Lab-item delete archives through `ServiceFindBackend` → `OperationService.perform` with a grant when required; receipt is recorded and replayable. Model tool can search and cannot delete, reindex, or donate. Donation goes through `FindTheThingOperation.donate`.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** No assumption of global Spotlight access to other apps or the entire Mac.

**Research:** [S02](../docs/SOURCE_INDEX.md#s02), [S06](../docs/SOURCE_INDEX.md#s06).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-006's spec now claims `implemented`. The domain and lexical fallback are proven by package tests on research. The Mac and iPhone hosts link the module. Nothing here is device-verified, and a live Spotlight donation round trip was not run.

**Changed:**

- `Packages/LabFeatures`: `FindTheThing` product and target; `FindTheThingTests` (24 tests in 2 suites).
- `Packages/LabFeatures/Sources/FindTheThing/` (new): index, operation, backend, fixtures, optional semantic retriever, and iOS/macOS `FindRecordEntity` / `IndexedEntityDonor`.
- `Apps/Shared/FindTheThing/` (new): host index, session, page, catalog launch.
- `Apps/Mac/Window/FindTheThingColumns.swift` (new).
- Hooks, one case each: `MainWindowState`, `MainWindow`, `SidebarView`, `LabCommands` (View › Find the Thing, ⌘9), `ExperimentDetailView`, `LabMacApp` / `LabPhoneApp` (`FindTheThingHost.connect()`), `ActionAtlasHost` (`FindTheThingIntentsPackage`), `ActionAtlasHostTests` entity/query expectations.
- `project.yml` and regenerated project: LabMac, LabPhone, and LabPhoneSurfaces link `FindTheThing`.
- `Config/ProductPolicy.txt`: CoreSpotlight for CoreLocal (macOS, iOS) and SystemSurfaces (iOS).
- `experiments/LAB-006-find-the-thing.md`: `state: implemented`, implemented split, implementation notes. Catalog JSON regenerated. LabCatalog tests expect 7 implemented (41 specified); M1 stays 6 of 6.
- `docs/SOURCE_INDEX.md` (S02), `docs/VERIFICATION_BOUNDARIES.md` (Indexed app entities ledger), rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** Installed SDK: `IndexedEntity`, `indexAppEntities`, `deleteAppEntities(identifiedBy:ofType:)` — macOS 15.0 / iOS 18.0 / visionOS 2.0; absent on watchOS and tvOS. No entitlement.
2. **Opted-in index.** `AppSearchIndex.apply` stores only `optedIn` records; packing slip is never a hit.
3. **Stable IDs and deep links.** UUID record IDs; `nativelab://find/<uuid>` (in-app name only).
4. **Lexical before semantic.** Lexical always runs; semantic is optional and defaults unavailable.
5. **Delete and reindex.** Audit counts; suppressed fixtures stay out until Reset Fixtures.
6. **Tests.** Cancellation, unsupported queries, unavailable store, authorization ceilings, archive receipts.

**Commands run:** listed in the LAB-006-A rows of [BUILD_STATUS](../docs/BUILD_STATUS.md). Narrow: `swift test --package-path Packages/LabFeatures --filter FindTheThingTests` (24 passed). Full host gate through `script/test.sh` with `LAB_SIMULATOR_PREFIX="NL LAB-006-A"` reached Mac, iPhone, Watch, and TV successfully before a research quiet window interrupted the release manifest; `python3 script/build_manifest.py` then passed. A later full Mac re-run failed five unrelated Share Ingress hosted tests; ActionAtlasHostTests and KeyboardAccessTests still passed with Find the Thing's metadata and ⌘9.

**Not run:**

- A physical device.
- A live `IndexedEntityDonor` against the system index / Spotlight UI.
- VoiceOver, Voice Control, and Full Keyboard Access passes.
- A 26-SDK compile.
- Watch or Apple TV hosts (API unavailable; module not linked).

**Next dependency-ready ticket:** LAB-006-B (qualification), once this ticket is integrated.
