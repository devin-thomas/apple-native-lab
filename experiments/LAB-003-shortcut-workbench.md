---
id: "LAB-003"
title: "Shortcut Workbench"
state: "implemented"
milestone: "M2"
category: "System surfaces"
depends_on: ["LAB-001", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-003 — Shortcut Workbench

## The moment

Turn the lab into a small typed automation toolbox, not a collection of launch-app commands.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac.

**Primary APIs:** AppIntents, Shortcuts, 27-generation Storage actions. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** RecipeDefinition, TypedActionContract, JobHandle. These are lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Offer a curated entry set separate from atomic actions
2. Build import-query-transform-export recipe walkthroughs
3. Persist entity references in a user-created shortcut
4. Inspect data passed into optional model steps

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A recipe survives renaming its source item.
- [ ] Cancellation does not leave half an import.
- [ ] Raw secret values never enter recipe exports.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Up to ten curated App Shortcuts is not a ten-action library cap. Platform packaging differs; never auto-install a personal automation.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Manual recipe instructions and app action browser; no secret storage inside Shortcuts.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Implemented module: `Packages/LabFeatures/Sources/ShortcutWorkbench/`, with host glue in `Apps/Shared/ShortcutWorkbench/` and Mac columns. Shared operations stay in LabDomain; Action Atlas supplies entities and the atomic library; curated App Shortcuts are declared here through `NativeLabAppShortcuts`.

## Delivery

[Implementation ticket](../tickets/LAB-003-A.md) → [qualification ticket](../tickets/LAB-003-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S03](../docs/SOURCE_INDEX.md#s03), [S04](../docs/SOURCE_INDEX.md#s04). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.

## Implementation notes (LAB-003-A)

**Module.** `ShortcutWorkbench` product in LabFeatures depends on LabDomain and ActionAtlas (for `LabItemEntity` and Find Lab Items as a curated phrase). Hosts link the product on Mac and iPhone (including LabPhoneSurfaces).

**Curated vs atomic.** Six curated App Shortcuts via `NativeLabAppShortcuts` / `AppShortcutsProvider` (Open Workbench, Run Import–Export Recipe, Resolve Lab Item, Inspect Model Step, Export Recipe, Find Lab Items). Atomic Create/Archive/Export remain Action Atlas-only. Cap is ten; this build uses six.

**Recipes.** `RecipeDefinition` holds stable `ItemID`s. Rename leaves the ID; resolve and recipe runs still find the item. Import drafts live in `RecipeImportStaging`; cancel removes the draft before any commit. `RecipeExport` and `ModelStepInspection` redact secret-shaped fields (`apiKey`, `password`, `token`, …) to `[redacted]`.

**Storage actions (S04).** Recipe and entity state are lab-owned (catalog + store identifiers). Shortcuts Storage is not used for secrets; the fallback copy forbids it. Concrete 27-generation Shortcuts Storage symbols were probed on the installed SDK during this ticket (see verification ledger).

**Fallback.** Manual recipe cards and the Action Atlas browser; no secret storage inside Shortcuts. Proven in package tests and the in-app workbench UI.

## Qualification notes (LAB-003-B)

State stays `implemented`; see the [qualification walkthrough](../docs/walkthroughs/LAB-003-shortcut-workbench.md). Local fixture and hosted backend invocations do not qualify Shortcuts, Siri, system Storage, a model, or cross-device entity resolution.

Qualification reproduces two limits: a fresh unbound four-step recipe commits its import, then refuses transform because the running value has no source binding; and export redaction covers secret-shaped model field names only, not arbitrary text. The complete fresh interaction and unrestricted secret-export criterion remain unqualified. A staged import committed separately and bound to query → transform → export is the usable fixture fallback. Authored recipes remain process-local. No product behavior or platform support changes in this qualification.
