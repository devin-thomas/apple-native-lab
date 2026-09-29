---
id: "CORE-005"
title: "Build native host navigation and the experiment registry"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-002", "CORE-003", "CORE-004"]
---

# CORE-005 — Build native host navigation and the experiment registry

## Goal

Create a pleasant native laboratory, not a wall of nonfunctional framework buttons.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Apps native host views and static feature descriptors.

## Implementation steps

1. Build Mac sidebar/detail, commands, Settings, and appropriate window behavior
2. Build adaptive iPhone catalog/detail/import navigation
3. Register experiments statically with lifecycle state, fallback, and source links
4. Add an action/receipt inspector and safe demo reset entry

## Acceptance criteria

- [x] Catalog entries distinguish specified from implemented features. (All six lifecycle states have their own symbol and word, never color alone. The Mac sidebar lists each state with its count, zero included, and an empty state explains itself; the iPhone catalog has a state filter and a legend of all six. `ExperimentRegistryTests` check the six states are distinct and split the catalog.)
- [x] Mac essential actions have keyboard/menu access. (Search ⌘F, Readiness ⇧⌘0, Reset Demo… ⇧⌘R, Show Receipt Inspector ⌥⌘I, Show Latest Receipt ⌥⌘L, Lab Collection ⌘1, All Experiments ⌘2, First Release Journey ⌘3, Settings ⌘,. Each was read from the running app's menus and pressed through UI scripting; sample selection moved with the arrow keys and Escape cancelled Reset Demo.)
- [x] Large text and small phone layouts do not hide the primary action. (iPhone 17e simulator, at the default size and at accessibility-extra-extra-extra-large: a UI journey asserted each screen's primary action was on screen and hittable without scrolling. Simulator only.)
- [x] The host remains usable offline without accounts or keys. (All data is local SQLite in the app's container; no source uses a network API; the sandboxed Mac app declares no network entitlement. The only URL is the public specification link, opened only when a person asks.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Status: blocked.** Every acceptance criterion above passed, but `script/test.sh` fails at its last step. The hosts now link LabStore, whose `DemoFixture` imports CryptoKit (CORE-003), and `Config/ProductPolicy.txt` does not allow CryptoKit for CoreLocal, so `script/build_manifest.py` fails CoreLocal with "LabMac: links CryptoKit … LabPhone: links CryptoKit". It needs two policy lines, which this ticket may not add:

```text
link         CoreLocal  macos    CryptoKit           # LabStore DemoFixture: SHA-256 of the bundled demo seed
link         CoreLocal  ios      CryptoKit           # same, iPhone host
```

With those lines in a throwaway copy of this branch, the manifest exited 0 (CoreLocal and Companions built), and CryptoKit was the only framework added since CORE-008. Mark this ticket done once the lines land and `script/test.sh` passes.

**Changed:**

- `Packages/LabFeatures/Sources/LabCatalog/`: new `ExperimentRegistration.swift`, `Registrations.swift` (48 compiled registrations with their fallbacks), `ExperimentRegistry.swift` (joins registrations with the spec-generated descriptors, catalog scopes including lifecycle state, search, state meanings), `RegisteredExperiment.swift`, `SourceLink.swift`; new `Tests/LabCatalogTests/ExperimentRegistryTests.swift`.
- `Apps/Shared/`: new `Library/` (`LabLibrary`, `LabDataService`, `LabStoreLocation`, `DemoSeedResource`, `LibraryMessages`), `Collection/` (sample rows and detail, namespace summary, Reset Demo confirmation, demo search), `Receipts/` (receipt record, presentation, and views), `PinnedActionBar.swift`; `Catalog/` and `Readiness/` hold the moved existing views, with `ExperimentDetailView`, `ExperimentRow`, `StateBadge`, `LabModel`, `ReadinessView`, and `CapabilityRow` updated.
- `Apps/Mac/`: `LabMacApp.swift`, new `LabCommands.swift`, `Window/` (main window, window state, sidebar, catalog and collection columns, receipt inspector), `Settings/SettingsView.swift`; removed `CatalogSplitView.swift`.
- `Apps/Phone/`: `LabPhoneApp.swift`, new `Tabs/` (Catalog, Collection, Import); removed `CatalogListView.swift`.
- `Tests/LabMacTests/LabLibraryHostTests.swift` (new).
- `project.yml` and the regenerated `AppleNativeLab.xcodeproj`: LabMac and LabPhone depend on LabDomain and LabStore, and both bundle `Fixtures/demo/seed.json` as a resource. Nothing else changed; Info.plists are unchanged.

**What exists now:**

- A compile-time registry (ADR-010). Every spec-generated descriptor needs exactly one Swift registration and the reverse, or the registry refuses to load. A registered experiment carries its lifecycle state (from its spec only), its declared fallback, and source links to its spec and tickets on the public repository, with the relative path always shown.
- Mac: one main window with sidebar (Lab Collection; All Experiments; milestones, states, and categories with counts), content, and detail columns, and a receipt inspector attached to the detail column. Commands for search, navigation, Reset Demo, and the inspector; a single Readiness window; a Settings scene with the data namespaces and Reset Demo. Scene storage keeps only which list and which experiment were showing.
- iPhone: tabs for Catalog (by milestone, searchable, state filter and legend), Collection (latest receipt, demo samples, namespaces; Reset Demo and Receipts in the navigation bar), Import (says the share inbox arrives with LAB-007 and links to it; nothing can be imported), and Readiness. Experiment and sample pages pin their primary action above the tab bar.
- Local state: `LabLibrary` opens `Application Support/Native Lab/Lab.sqlite` in the app's own container (inside the sandbox container on the Mac). On first run, when the demo namespace is empty, it seeds through `resetDemo` as the app-UI actor. It never resets an existing demo unasked. The collection browser reads the 3 demo collections and 12 samples through `OperationService`. Every change (Reset Demo, archive and restore of a sample, a receipt's undo) goes through `OperationService`; no view sees the store or the service. The user namespace is only counted.
- Receipt inspector: operation title, entry point, operation and request IDs, status (a conflict says which revisions), summary, each affected or removed entity with its revisions, and the undo offer or why there is none. An undo runs as a new request; a stale one comes back as a conflict receipt and changes nothing. Receipts are kept for the session only.
- Reset Demo is an alert with Cancel on both platforms. On iPhone a confirmation dialog opened as a popover with no Cancel button.

**Evidence:** the CORE-005 rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). Screenshots were kept outside the repository.

**Not run:** any physical device; VoiceOver speech itself (labels were read through the Accessibility API instead); Full Keyboard Access, Reduce Motion, and Increase Contrast (system settings were not changed); iPad layouts; a 26-SDK compile.

**Known limitations:**

- On the Mac, Tab from the search field moved focus to the inspector's receipt list rather than the results list; arrow keys and every command work.
- At the largest accessibility size the receipt's undo offer needed one scroll on iPhone 17e; it is the second section of the receipt.
- `OperationService` has no read that lists or counts collections, so `LabDataService` reads the store directly for the namespace census, returning counts only.

**Next dependency-ready tickets:** CORE-010 (needs CORE-005 and CORE-007) once this ticket is done; CORE-006 is in progress elsewhere. Every LAB-nnn-A ticket also waits on CORE-006.

**Integration (2026-09-29):** the integrator allowed CryptoKit for CoreLocal in `Config/ProductPolicy.txt` (the LabStore demo fixture hashes the bundled seed), which cleared the manifest blocker. The host now composes `OperationService` with `GrantAuthorizationPolicy` (ADR-013): each destructive change gets a 30-second grant for that operation only, issued for a user action or the first-run seed of an empty demo namespace, and revoked after the commit. `LabGrantHostTests` cover it; `script/test.sh` passes, and the Mac hosted suite runs 15 tests.
