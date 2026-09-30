---
id: "LAB-007"
title: "Share Ingress Station"
state: "implemented"
milestone: "M1"
category: "Sharing"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-007 — Share Ingress Station

## The moment

Share a page, image, or video into a staging inbox without losing the source context.

## Scope and native leverage

**Hosts:** iPhone, iPad; separate Mac Share extension.

**Primary APIs:** Share extensions, NSItemProvider, App Groups. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** ImportEnvelope, StagedAttachment. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Accept URL/text/image/movie attachments
2. Copy bounded data while extension access is valid
3. Write a durable inbox entry and finish promptly
4. Let the host app validate and process the staged item

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Cloud-backed attachments can be cancelled safely.
- [ ] Multiple attachments preserve order and provenance.
- [ ] Malformed and oversized payloads never block future imports.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Share extensions have constrained lifetime/memory. They do not scrape the host app or run a large media pipeline.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Host-app file picker and paste action; extension not required for core build.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/share-ingress-station/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-007-A):

- `Packages/LabFeatures/Sources/ShareIngress/`: the intake both the extension and the hosts run (`IngressStation`), the attachment sources (`ItemProviderAttachment` for share-sheet and pasteboard providers, `ChosenFile` for picked and dropped files), the origin records kept beside each staged import (`ImportOrigin`, `OriginLog`), and the review list (`ShareInbox`). It depends on LabDomain and LabStaging, never on the store.
- `Extensions/ShareExtension/`: the iOS share extension (SystemSurfaces). It stages into the App Group folder and finishes.
- `Extensions/PhoneSurfacesHost/`: the Info.plist and entitlements of `LabPhoneSurfaces`, the iPhone host variant that embeds the extension. It is built from LabPhone's sources, with LabPhone's bundle identifier, under its own scheme `LabPhone-Surfaces`.
- `Apps/Shared/ShareInbox/`: the host model and review views. Adoption goes through `LabLibrary.adoptImport` and `LabDataService.adoptImport` to `ImportAdopter` and the one `OperationService`. iPhone shows it on the Import tab; the Mac has a Share Inbox sidebar destination and View › Share Inbox (⌘6; ⌘5 until LAB-035-A took it at integration).

## Implementation notes (LAB-007-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs, on the Mac and in an iOS 27.0 simulator. These are compile and simulator facts, not device proof.

- Each shared attachment becomes its own staged import, in the order the share sheet listed it, with an origin record: the surface (share sheet, paste, file picker, drop), the time, the intake it came with, its position and the intake's size, and the declared type. The CORE-006 staging record refuses fields it does not define, so the origin sits in a separate `origins/` folder beside the staging folder. It is display data. A missing, forged, or mismatched origin reads as unknown and changes nothing else.
- The folder, not the origin, decides the adapter. The host's own container can only be written by the host, so its imports are adopted as the app UI. The App Group folder is written by the share extension, so its imports are adopted as the share extension. Either way the person's Add issues a grant for exactly that one new item, and it is revoked when the commit returns (ADR-013).
- A share of more than 32 attachments is refused whole, before anything is read. A file larger than the share's remaining 1 GiB budget is refused before it is copied. A malformed, oversized, or unsupported attachment is refused on its own. The others in the same share still stage, and nothing blocks the next share.
- A file-backed provider's URL is valid only inside `loadFileRepresentation`'s completion handler, so the handler clones the file into a scratch folder; staging then streams the copy. Cancelling cancels the provider's `Progress` and returns at once, even when the provider never calls back. A late callback copies nothing. A cancelled intake removes everything it had staged. In the test run, cancelling a provider's `Progress` reached the provider's own `Progress` asynchronously.
- Images and movies stage, validate, and list, but cannot be added: the domain has no attachment entity yet (`ImportRejection.attachmentsNotAdoptable`). Text over 2,000 characters stages but cannot become an item note. Text and links are added as one item each.
- The share extension refuses a file reference (`public.file-url`), so another app cannot point it at files the extension can read. The host's paste accepts one, because the person copied that file and the system grants access to it. On the sandboxed Mac a file URL on the pasteboard was readable this way.
- A sandboxed Mac app can show an open panel only with a user-selected file entitlement. Without one, AppKit logged "Unable to display open panel: your app is missing the User Selected File Read app sandbox entitlement", so LAB-007-A disabled Choose Files on the Mac with that reason. The host reads its own signature at launch (`ShareInboxModel.fileSelectionAllowed`), and accepts either `com.apple.security.files.user-selected.read-only` or `…read-write`. Correction (LAB-007-B): since LAB-008-A the CoreLocal Mac host carries `com.apple.security.files.user-selected.read-write`, so Choose Files is on there. It showed the open panel and imported the chosen files on the Mac (see Qualification notes). A sandboxed build without either entitlement still shows the button disabled with its reason.
- An iOS simulator build signs the App Group entitlement with no team, and at run time `containerURL(forSecurityApplicationGroupIdentifier:)` returned the shared container to both the app and the extension. A device build needs a team that can use App Groups; a free Personal Team cannot.
- There is no Mac share extension. A sandboxed Mac extension would need its own App Group, which Xcode would not sign without a development certificate (CORE-008).

## Qualification notes (LAB-007-B)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs at source revision 074eaaa: package and hosted tests on the Mac, a manual run of the Mac app driven through the Accessibility API, and a UI-test harness in an iPhone 17 Pro simulator on iOS 27.0. None of it is a device run of the share extension.

- On the Mac, Choose Files… showed the open panel, and one file, then three at once, arrived as File picker imports in the panel's order ("2 of 3", "3 of 3"). A file chosen again was recognized as already waiting and kept its first origin.
- In the simulator, the Paste button, the document picker (On My iPhone), and a share of an image and a movie from Photos all reached the inbox with their origins. The share listed the image and the movie as "1 of 2" and "2 of 2", marked Share sheet.
- A file provider's coordinated read is cancellable: with a writer holding the file, as a download does, cancelling the intake returned at once and kept nothing. A real iCloud download has still not been cancelled.
- Limits hold at their real values: text 1 byte over 2 MiB and a file 1 byte over the 1 GiB share budget are refused from their size, before anything is kept, and the next share stages.
- Finding: the inbox orders intakes by the second they began, then by their random batch ID. Two intakes in the same second can list the later first. Order within one intake is always kept.
- Finding: the same text pasted and added, then shared from another app and added to the same collection, derives the same request ID from another adapter. The service refuses it as a reused request, the Add reports "This import conflicts with an earlier request. Share it again.", and sharing again cannot help. Nothing is stored twice and nothing else is blocked; the import waits until the person removes it.
- An approval issued to one adapter reads as out of scope, not missing, for another adapter's import. Either way nothing commits.

## Delivery

[Implementation ticket](../tickets/LAB-007-A.md) → [qualification ticket](../tickets/LAB-007-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S13](../docs/SOURCE_INDEX.md#s13), [S11](../docs/SOURCE_INDEX.md#s11). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
