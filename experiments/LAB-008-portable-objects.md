---
id: "LAB-008"
title: "Portable Objects"
state: "implemented"
milestone: "M1"
category: "Sharing"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-008 — Portable Objects

## The moment

Drag a rich lab object into another window or export it as a inspectable document.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac.

**Primary APIs:** Transferable, UTType, document import/export. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** LabDocument v1, RepresentationDescriptor. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Provide native document, JSON, text, and URL representations where meaningful
2. Show an export preview with fields and destination
3. Validate imports before committing
4. Preserve unknown fields in a versioned extras map

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Unicode and empty optional fields round-trip.
- [ ] A path-traversal attachment is rejected.
- [ ] Reimporting one document does not duplicate stable items.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Transfer representations are adapters, not automatic clipboard parity on every platform.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

File picker and explicit export preserve the full native document.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/portable-objects/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-008-A):

- `Packages/LabFeatures/Sources/PortableObjects/`: the `LabDocument` v1 model and its lossless JSON tree, the mapping between a document and a stored item (`DocumentMapping`), the import plan, `PortableObjectsImporter` (staging through `LabStaging`, then one commit through the backend's `OperationService`), the `Transferable` types (`PortableObject` out, `IncomingObject` in), `UTType.labObject`, `RepresentationDescriptor`, `ExportPreview`, and the bundled sample object. It depends on LabDomain and LabStaging and never holds the store.
- `Packages/LabDomain`: `ItemExtras`, the item metadata an import keeps (`LabItem.extras`, `ItemDraft.extras`). `Packages/LabStore` writes it once, when an item's row is inserted, and reads it back.
- `Apps/Shared/PortableObjects/`: the per-window session and `LibraryPortableBackend` (reads as the app UI through `LabDataService`, commits through `LabLibrary.submit`), the export preview, the import review, and the iPhone screen. The Mac reaches it from the sidebar and View › Portable Objects (⌘5), with its columns in `Apps/Mac/Window/PortableObjectsColumns.swift`. The iPhone reaches it from this experiment's catalog page (Open Portable Objects), with no new tab.
- `Fixtures/LAB-008/`: hostile documents. The valid sample is a resource of the module.

## Implementation notes (LAB-008-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs on macOS 27.0. These are Mac and simulator facts, not device proof.

- `Transferable` export and import work from a package target. `exported(as:)`, `init(importing:contentType:)`, and `export(to:contentType:)` are macOS 15.2 and iOS 18.2 APIs, under the 26 floor. `UTType(exportedAs:conformingTo:)` gives a type its conformance only when an Info.plist declares it: in a package test the lab type does not conform to `public.json`; in the app it does, and `UTType(filenameExtension: "anlab")` resolves to it.
- `dropDestination(for:isEnabled:action:)` with a `DropSession` is the 26 API. `onDropSessionUpdated` is iOS 27 and later, above the floor, so the drop area has no hover highlight; the system's copy badge shows.
- A drag from a row or the export card between two Mac windows carries the complete document. The receiving window stages it and recognizes it by identity.
- A drag into TextEdit inserts the labeled plain-text summary. A drag into Finder offers a file promise and a file URL, and Finder accepted the promise. It then logged "Sandbox extension data required immediately for flavor com.apple.pastelocation, but failed to obtain. (-20)", and no file was written. That drag was synthetic (posted mouse events). A person's drag to Finder has not been run. Save with Export… writes the file.
- The sandboxed Mac app needs `com.apple.security.files.user-selected.read-write` for the Import and Export dialogs. Without it, AppKit logs "Unable to display open panel: your app is missing the User Selected File Read app sandbox entitlement" and shows nothing. It is an ordinary sandbox entitlement that needs no provisioning, and it covers only the files a person picks. It is declared for CoreLocal on macOS in `Config/ProductPolicy.txt`.
- On the Mac, an `accessibilityLabel` on selectable text (`.textSelection(.enabled)`) crashed the app. When an assistive app outside the process read the text's children, SwiftUI resolved the label through AppKit's control cascade until the stack overflowed (`EXC_BAD_ACCESS`, stack guard). In-process reads, as in the hosted accessibility tests, did not reproduce it. The export preview's JSON text has no custom label.
- Builds with different bundle prefixes on one Mac each declare `.anlab`, and Launch Services types the file with one of them. Importers therefore also accept `public.json`.
- A document that lists attachments is refused at review. The domain has no attachment entity yet, and keeping the descriptors without the bytes would export a document whose attachments do not exist. The codec reads, validates, and writes attachment descriptors, so an `.anlabpack` or attachment entity can build on it.

## Delivery

[Implementation ticket](../tickets/LAB-008-A.md) → [qualification ticket](../tickets/LAB-008-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S11](../docs/SOURCE_INDEX.md#s11), [S12](../docs/SOURCE_INDEX.md#s12). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
