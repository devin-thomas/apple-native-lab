---
id: "LAB-009-A"
title: "Implement Documents Everywhere"
status: "done"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-009-A — Implement Documents Everywhere

## Goal

Preview a custom document in the system and browse an opt-in sample provider.

## Authority and scope

Read the [governing specification](../experiments/LAB-009-documents-everywhere.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** documents-everywhere module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Ship Quick Look support first
3. Add a separate local-fixture provider target
4. Enumerate and open tiny safe sample documents
5. Test conflicts and eviction before remote storage
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Quick Look works without provider activation. (`DocumentPreviewBuilder` builds HTML/plain text from `.anlab` bytes with `ProviderSession` disabled: `DocumentPreviewTests`. The same builder is what `QuickLookPreview` (`QLPreviewProvider`) uses. Hosted Mac session opens samples with `providerState == .disabled`. Live Finder/Files Quick Look on a device was not run.)
- [x] External edits preserve document revision rules. (`RevisionRulesTests` and `ProviderSessionTests.externalEditOnAMirrorPreservesRevisionRules`: matching base accepts; stale base returns conflict and leaves the current revision.)
- [x] Provider disconnect never deletes the authoritative source. (`ProviderSessionTests.disconnectNeverDeletesTheAuthoritativeSource` and eviction: mirrors clear; catalog bytes remain.)
- [x] Fallback is usable: Document browser with previews; provider remains disabled until qualified.. (Mac: Documents Everywhere sidebar and ⌘9; iPhone: catalog Open Documents Everywhere. Activate Sample Provider… is disabled. Provider stays `.disabled`.)
- [x] Sensitive operations share the domain authorization/receipt path. (`SampleAdopter` → `PortableObjectsImporter` → `OperationService`; `SampleCatalogTests.adoptGoesThroughTheImporterAndLeavesAReceipt`.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** File Provider is a serious storage extension, not needed for ordinary sharing. No production cloud service in v1.

**Research:** [S14](../docs/SOURCE_INDEX.md#s14), [S22](../docs/SOURCE_INDEX.md#s22).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-009's spec now claims `implemented`. The document browser and domain preview path ran through package and Mac hosted tests with the File Provider disabled. The Quick Look preview extension is embedded in SystemSurfaces. Nothing here is device-verified. The live File Provider is not activated.

**Changed:**

- `Packages/LabFeatures`:
  - `DocumentsEverywhere` product and target (new): `ProviderItem`, `DocumentRevision`, `RevisionRules`, `ProviderSession`, `SampleCatalog`, `DocumentPreviewBuilder`, `SampleAdopter`, errors; bundled `harbor-note.anlab` and `tide-card.anlab`.
  - `DocumentsEverywhereTests` (new): 19 tests across preview, revision, provider session, and adopt.
  - `LabCatalogTests` expect 7 implemented experiments.
- `Apps/Shared/DocumentsEverywhere/` (new): session and browser views.
- `Apps/Mac/Window/DocumentsEverywhereColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState` has `.documentsEverywhere` and the per-window session.
  - `MainWindow` has the columns, search prompt, and environment open action.
  - `SidebarView` has the row.
  - `LabCommands` has View › Documents Everywhere (⌘9).
  - `ExperimentModuleAction` / `ExperimentDetailView` open the browser and show the module summary.
- `Extensions/QuickLookPreview/` (new, SystemSurfaces): `DocumentPreviewProvider`, embedded by `LabPhoneSurfaces`.
- `Extensions/DocumentsProvider/` (new sources + README): local-fixture File Provider shell. Not attached to a FrontierOptional scheme yet; domain tests cover disconnect/eviction. Lead: FrontierOptional host wiring for LAB-009-B.
- `project.yml` and regenerated `AppleNativeLab.xcodeproj`: LabMac / LabPhone / LabPhoneSurfaces link `DocumentsEverywhere`; QuickLookPreview target and scheme entry; LabPhoneSurfaces declares the lab object UTType.
- `Config/ProductPolicy.txt`: QuickLook and QuickLookSupport for SystemSurfaces on iOS.
- `Config/Profiles/SystemSurfaces.xcconfig`: comments name QuickLookPreview.
- `Fixtures/LAB-009/`: samples and hostile inputs.
- `experiments/LAB-009-documents-everywhere.md`: `state: implemented`, split, notes. Catalog regenerated.
- `docs/VERIFICATION_BOUNDARIES.md`: Documents Everywhere ledger rows. `docs/BUILD_STATUS.md`: scheme row and evidence rows.
- This record.

**Implementation steps:**

1. **Probe.** Installed SDK headers for `QLPreviewProvider` / `QLPreviewReply` (iOS 15 / macOS 12) and File Provider item versions. Document Quick Look is not AR Quick Look (S22). Ledger updated.
2. **Quick Look first.** Shared `DocumentPreviewBuilder`; SystemSurfaces preview extension; CoreLocal browser uses the same builder with provider disabled.
3. **Provider target.** Sources under `Extensions/DocumentsProvider/`; FrontierOptional host not created in this ticket so CoreLocal stays clean.
4. **Enumerate/open.** `SampleCatalog` with two original fixtures.
5. **Conflicts/eviction.** `RevisionRules` and `ProviderSession` tests before any remote storage.
6. **Tests.** Domain operation (adopt), cancellation, invalid input, unavailable/missing sample.

**Not run:**

- Physical device.
- Live Finder/Files Quick Look with the extension.
- Mac Quick Look extension (no LabMacSurfaces host).
- Live File Provider domain registration.
- VoiceOver / Voice Control / Full Keyboard Access passes.
- A 26-SDK compile.

**Next dependency-ready ticket:** LAB-009-B (qualify Documents Everywhere), once the lead merges this branch. FrontierOptional File Provider host embedding needs a lead decision.
