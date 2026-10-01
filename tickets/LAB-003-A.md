---
id: "LAB-003-A"
title: "Implement Shortcut Workbench"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-008-B"]
---

# LAB-003-A — Implement Shortcut Workbench

## Goal

Turn the lab into a small typed automation toolbox, not a collection of launch-app commands.

## Authority and scope

Read the [governing specification](../experiments/LAB-003-shortcut-workbench.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** shortcut-workbench module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Offer a curated entry set separate from atomic actions
3. Build import-query-transform-export recipe walkthroughs
4. Persist entity references in a user-created shortcut
5. Inspect data passed into optional model steps
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] A recipe survives renaming its source item. (`RecipeOperationTests.aRecipeSurvivesRenamingItsSourceItem`: bind `ItemID`, rename through `OperationService`, recipe query/export still resolve the same ID with the new title. `WorkbenchIntentTests.resolveIntentFindsAnItemAfterRename` does the same through `ResolveLabItemIntent`.)
- [x] Cancellation does not leave half an import. (`cancellationDoesNotLeaveHalfAnImport`, `cancellingAfterStagingBeforeCommitLeavesNothing`: `RecipeImportStaging` draft removed; store item count unchanged; commit after cancel throws `importIncomplete`.)
- [x] Raw secret values never enter recipe exports. (`rawSecretValuesNeverEnterRecipeExports`, `exportRecipeIntentRedactsSecrets`, `modelStepInspectionRedactsSecrets`: `apiKey` / `password` / `token` / `clientSecret` become `[redacted]`; raw values absent from export bytes.)
- [x] Fallback is usable: Manual recipe instructions and app action browser; no secret storage inside Shortcuts.. (`fallbackCopyMatchesTheRegistration` matches the registration fallback verbatim; `ManualRecipeCard.all` ships the walkthroughs; Action Atlas remains the atomic browser. In-app Shortcut Workbench page shows the cards. No Shortcuts Storage write path exists in this module.)
- [x] Sensitive operations share the domain authorization/receipt path. (`sensitiveTransformSharesTheDomainCommitPath`: transform is one `updateItem` through `WorkbenchBackend.commit` / `OperationService` with `.appControl` authority and a receipt.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Up to ten curated App Shortcuts is not a ten-action library cap. Platform packaging differs; never auto-install a personal automation.

**Research:** [S03](../docs/SOURCE_INDEX.md#s03), [S04](../docs/SOURCE_INDEX.md#s04).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-003's spec now claims `implemented`. Package tests and a Mac build with App Intents metadata proved the domain contract and curated entries. Nothing here is device-verified. Shortcuts was not opened on a device or the Mac.

**Where it lives.** New `ShortcutWorkbench` product/target in `Packages/LabFeatures`, depending on LabDomain and ActionAtlas (entities + Find Lab Items as a curated phrase). Host glue in `Apps/Shared/ShortcutWorkbench/`; Mac columns and ⌥⌘8. `NativeLabAppShortcuts` is the first `AppShortcutsProvider` in the lab (six curated entries, under the ten-cap).

**Changed:**

- `Packages/LabFeatures/Package.swift`: `ShortcutWorkbench` product/target and tests.
- `Packages/LabFeatures/Sources/ShortcutWorkbench/` (new): `RecipeDefinition`, `TypedActionContract`, `JobHandle`, `SecretRedaction`, `RecipeExport` / model-step inspection, `WorkbenchActions` / backend / link, `RecipeImportStaging`, manual fallback cards, App Intents, `NativeLabAppShortcuts`.
- `Packages/LabFeatures/Tests/ShortcutWorkbenchTests/` (new).
- `Apps/Shared/ShortcutWorkbench/` (new): host connect, model, views, launch.
- Hooks (one case each): `NativeLabIntentsPackage` includes `ShortcutWorkbenchIntentsPackage`; `LabMacApp` / `LabPhoneApp` connect; `MainWindowState` / `MainWindow` / `SidebarView` / `LabCommands` (⌥⌘8); `ExperimentDetailView` / `ExperimentModuleAction`.
- `project.yml` + regenerated project: LabMac, LabPhone, LabPhoneSurfaces link `ShortcutWorkbench`.
- Catalog: experiment `state: implemented`; JSON regenerated; LabCatalog tests expect 7 implemented / 41 specified.
- `docs/VERIFICATION_BOUNDARIES.md`, `docs/SOURCE_INDEX.md` (S03/S04), `docs/BUILD_STATUS.md`, `Fixtures/LAB-003/README.md`.

**Implementation steps:**

1. **Probe.** iOS 27.0 AppIntents.swiftinterface: `AppShortcutsProvider` / `AppShortcut` present. No Shortcuts Storage type by that name; durable identity is `PersistentlyIdentifiable`. Ledger updated.
2. **Curated set.** Six App Shortcuts, separate from Action Atlas atomic Create/Archive/Export.
3. **Recipes.** Import → query → transform → export walkthrough; sources are stable `ItemID`s.
4. **Entity refs.** Resolve-after-rename proven in package tests and Resolve Lab Item intent.
5. **Model step inspection.** Redacts secret-shaped fields; never stored in Shortcuts.
6. **Tests.** Domain, cancel, invalid input, unavailable path in package tests; hosted smoke checks curated contracts and fallback copy.

**Not run / incomplete:**

- Physical device; Mac Shortcuts app; Siri; AppIntentsTesting.
- Full `script/test.sh` iPhone simulator step hung (`test runner hung before establishing connection`); a focused Mac hosted re-run waited on research's Mac UI lock behind other workers and was stopped. Lead should re-run `LAB_SIMULATOR_PREFIX="NL LAB-003-A" script/test.sh` when research is clear.
- VoiceOver / Voice Control / Full Keyboard Access; 26-SDK compile.

**Next dependency-ready ticket:** LAB-003-B (qualification), once the lead confirms the four-platform gate on a clear research.
