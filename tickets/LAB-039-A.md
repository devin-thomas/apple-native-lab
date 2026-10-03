---
id: "LAB-039-A"
title: "Implement Tiny Doorway"
status: "done"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-008-B"]
---

# LAB-039-A — Implement Tiny Doorway

## Goal

Scan a code or open a link and arrive at one tightly scoped native action instead of a giant onboarding funnel.

## Authority and scope

Read the [governing specification](../experiments/LAB-039-tiny-doorway.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** tiny-doorway module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use an original local demo action
3. Validate domain/path and untrusted parameters
4. Offer a minimal App Clip target after setup
5. Hand off confirmed state to the full app when supported
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Malformed links cannot execute privileged actions. (`ValidationTests` + `Fixtures/LAB-039/links.json`: wrong host, privileged path/query, unknown item, unsupported scheme, credentials. No proposal → no `DomainOperation`.)
- [x] Offline invocation has an explained fallback. (`ValidationTests.offlineBlocksHTTPSButNotDeepLinks` and `DoorwayFallback.offlineExplanation`.)
- [x] No public hosting dependency is required for core build. (Fictional `doorway.nativelab.example` host; CoreLocal links no AppClip and declares no associated domains.)
- [x] Fallback is usable: Web information page or full-app deep link, with no forced installation promise. (Local information page copy; `nativelab://doorway/…` deep links; Confirm Visit through the receipt path. App Clip status explains the deployment gate.)
- [x] Sensitive operations share the domain authorization/receipt path. (Confirm Visit → `DoorwayAction.visitOperation` → `LabLibrary.submit` / `OperationService` with receipt and undo. A link never issues a grant.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** App Clip invocation needs deployment configuration; a custom URL scheme alone is not equivalent.

**Research:** [S52](../docs/SOURCE_INDEX.md#s52).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State claimed: implemented.** Package tests prove validation, visit receipts, offline/deep-link fallbacks, and the not-configured App Clip path. Nothing is device-verified. No App Clip was invoked. The branch is `ticket/LAB-039-A`.

**The action.** A doorway link may request only `/open/visit?item=<demo-uuid>`. After review, Confirm Visit appends `Visited via Tiny Doorway.` to that demo sample's note through `updateItem` at the revision shown, with a receipt that offers an undo. Reset Visits strips only that marker. Entering the experiment or validating a link does not grant permission.

**Changed:**

- `Packages/LabFeatures/Package.swift`: `TinyDoorway` product/target and `TinyDoorwayTests`.
- `Packages/LabFeatures/Sources/TinyDoorway/` (new): `DoorwayPolicy`, `InvocationContext`, `SignedLinkProposal`, `DoorwayValidator`, `DoorwayAction`, `DoorwayError`, `DoorwayFallback` / `DoorwayClipStatus`, `DoorwayHandoff`, `DemoLinks`.
- `Packages/LabFeatures/Tests/TinyDoorwayTests/` (new): 20 tests in 3 suites.
- `Fixtures/LAB-039/` (new): `links.json` and README.
- `Apps/Shared/TinyDoorway/` (new): `DoorwaySession`, `DoorwayViews`, `TinyDoorwayPage` / `TinyDoorwayLaunch`.
- `Apps/Mac/Window/TinyDoorwayColumns.swift` (new).
- Shared hooks (one case each): `MainWindowState`, `MainWindow`, `SidebarView`, `LabCommands` (⌃⌥⌘1), `ExperimentDetailView`.
- `project.yml` + regenerated `AppleNativeLab.xcodeproj`: LabMac, LabPhone, LabPhoneSurfaces link `TinyDoorway`. No new entitlement.
- `experiments/LAB-039-tiny-doorway.md`: `state: implemented`, module split, implementation notes. Catalog regenerated.
- `docs/SOURCE_INDEX.md` (S52), `docs/VERIFICATION_BOUNDARIES.md` (App Clips ledger), `docs/BUILD_STATUS.md` rows, LabCatalog test counts 6→7.

**Implementation steps:**

1. **Probe.** Installed `AppClip.framework` headers read on research; findings in the spec notes and BUILD_STATUS.
2. **Demo action.** Visit marker on an allowlisted demo sample.
3. **Validate.** Host, path, allowlisted query, no credentials, no privileged segments/keys.
4. **App Clip.** Status reports not configured; same URL validator; no CoreLocal App Clip target (FrontierOptional / associated domains remain external).
5. **Handoff.** `DoorwayHandoff` value snapshot after confirm (Codable; not a grant).
6. **Tests.** Domain operation, cancellation between resets, invalid input, stale revision, duplicate request, unavailable clip, offline fallback.

**Evidence:** LAB-039-A rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Not run:** App Clip invocation, associated domains / AASA, physical iPhone, NFC/visual code, location confirmation, person VoiceOver/Voice Control/Full Keyboard Access passes, Mac hosted UI automation for this experiment.
