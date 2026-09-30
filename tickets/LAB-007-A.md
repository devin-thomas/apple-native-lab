---
id: "LAB-007-A"
title: "Implement Share Ingress Station"
status: "done"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-007-A — Implement Share Ingress Station

## Goal

Share a page, image, or video into a staging inbox without losing the source context.

## Authority and scope

Read the [governing specification](../experiments/LAB-007-share-ingress-station.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** share-ingress-station module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Accept URL/text/image/movie attachments
3. Copy bounded data while extension access is valid
4. Write a durable inbox entry and finish promptly
5. Let the host app validate and process the staged item
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Cloud-backed attachments can be cancelled safely. (Fixture path. `CancellationTests` stands in a provider that is still "downloading" and never calls back: cancelling the intake cancels the provider's `Progress`, returns at once, keeps nothing the share had staged, and leaves no incoming folder or scratch copy. A callback that arrives later copies nothing, and the next share stages normally. A slow byte stream cancelled mid-file leaves no partial file. The file picker reads through a cancellable `NSFileCoordinator`. A real iCloud download was not cancelled.)
- [x] Multiple attachments preserve order and provenance. (One share of a link, text, an image, and a movie stages four imports in the source's order. Each has an origin record with the surface, time, intake, position "n of 4", and declared type (`multipleAttachmentsKeepTheirOrderAndProvenance`). The inbox lists both folders in arrival order, and every row and review screen shows where the import came from. In the iOS simulator, a Photos share and a Safari share each reached the inbox marked "Share sheet"; the Safari link kept its page title.)
- [x] Malformed and oversized payloads never block future imports. (One share mixing good text, ill-formed UTF-8, a `file:` link, a link with a password, a `../` file name, and a PDF stages the two good items and refuses the other five, each by position with no content in the message. Oversized text, a file past the share's remaining budget, and 33 attachments are refused, the last before anything is read. A damaged waiting import is set aside and the rest still list. Each test then stages another share successfully.)
- [x] Fallback is usable: Host-app file picker and paste action; extension not required for core build.. (CoreLocal builds with no App Group. iPhone, iOS 27.0 simulator: Paste on the Import tab, then review, a new collection, Add, and the receipt; Choose Files picked a file from On My iPhone. Mac: Edit › Paste in the Share Inbox (⌘5), then Add, and the receipt in the inspector. The sandboxed Mac cannot show an open panel without an entitlement CoreLocal does not carry, so Choose Files is disabled there with the reason; a file copied to the pasteboard pasted in instead. See the Mac file picker below.)
- [x] Sensitive operations share the domain authorization/receipt path. (Every Add goes `ShareInboxModel.add` → `LabLibrary.adoptImport` → `LabDataService.adoptImport` → `ImportAdopter` → `OperationService.perform`. The adapter is the folder's: app UI for the host's folder, share extension for the App Group folder. A 30-second grant for exactly that one new item is revoked when the commit returns. Without it nothing commits (`withoutTheAddGrantNothingIsAdopted`). Instruction-like shared text (`Fixtures/hostile/prompt-injection.txt`) became exactly one item note; no collection was archived, the demo stayed 12 items, and no grant outlived the commit (`instructionLikeSharedTextStaysData`, `instructionLikeSharedTextIsAddedOnlyAsANote`).)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Share extensions have constrained lifetime/memory. They do not scrape the host app or run a large media pipeline.

**Research:** [S13](../docs/SOURCE_INDEX.md#s13), [S11](../docs/SOURCE_INDEX.md#s11).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

LAB-007's spec now claims `implemented`, because the fallback ran on the Mac and in the iOS simulator, and so did a real share from Photos and from Safari into the extension. Nothing is device-verified.

**Where the pieces live, and why.**

- `Packages/LabFeatures/Sources/ShareIngress/` (new target and product). The extension and both hosts run the same intake and read the same inbox, so it is a package. It depends on LabDomain and LabStaging and never on the store:
  - `IngressStation` stages one share, attachment by attachment.
  - `ItemProviderAttachment` and `ChosenFile` load share-sheet, pasteboard, picked, and dropped items.
  - `ImportOrigin` and `OriginLog` keep where each import came from.
  - `ShareInbox` lists and removes waiting imports.
- `Extensions/ShareExtension/` (new, SystemSurfaces): `ShareViewController`, `ShareSession`, `ShareSheetView`, its Info.plist and entitlements. It stages into the App Group folder and finishes.
- `Extensions/PhoneSurfacesHost/` (new): the Info.plist and entitlements of `LabPhoneSurfaces`.
  - A share extension must be embedded in an app, and `build_manifest.py` assigns a scheme to a profile by its application targets. So the `LabPhone-Surfaces` scheme builds a SystemSurfaces host variant, as `docs/BUILD_AND_DISTRIBUTION.md` describes.
  - The host variant has LabPhone's sources and bundle identifier, so on a device it replaces the CoreLocal app instead of taking another slot.
  - The variant also declares the App Group, because it has to read the folder the extension writes. CoreLocal declares none.
- `Apps/Shared/ShareInbox/` (new): `ShareInboxModel` and the review views, shared by iPhone and Mac.
- Shared host files, one hook each:
  - `Apps/Phone/Tabs/ImportTab.swift`: the placeholder is replaced by the inbox.
  - `Apps/Mac/Window/ShareInboxColumns.swift` (new).
  - `MainWindowState` (`.shareInbox`, `inboxEntry`), `MainWindow`, `SidebarView`, and `LabCommands` (View › Share Inbox, ⌘5).
  - `Apps/Shared/Library/LabDataService.swift` and `LabLibrary.swift`: one additive `adoptImport` each, because only `LabDataService` holds the service and the grant ledger, and only `LabLibrary` lists receipts.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `ShareIngress` product, target, and tests, and a LabStaging dependency.
- `Packages/LabFeatures/Tests/ShareIngressTests/` (new): 29 tests in 4 suites.
- `Tests/LabMacTests/ShareInboxHostTests.swift` (new): 8 hosted tests.
- `project.yml` and the regenerated project:
  - LabMac and LabPhone link `ShareIngress`.
  - New targets `LabPhoneSurfaces` and `ShareExtension`, and the scheme `LabPhone-Surfaces`.
- `Config/ProductPolicy.txt`:
  - `CoreFoundation` for every profile. URL resource-value keys come from it, now that the hosts link LabStaging.
  - For SystemSurfaces on iOS: the host variant's frameworks (the same as LabPhone's), CryptoKit, and the `com.apple.security.application-groups` entitlement.
- `Config/Profiles/SystemSurfaces.xcconfig`: its comment names the targets now attached.
- `experiments/LAB-007-share-ingress-station.md`: `state: implemented`, the module split, and implementation notes.
- The regenerated catalog JSON. `ExperimentCatalogTests` and `ExperimentRegistryTests` now expect two implemented experiments.
- `docs/BUILD_STATUS.md`: the scheme row, a corrected identifier note, and evidence rows. `docs/BUILD_AND_DISTRIBUTION.md`: the SystemSurfaces scheme cell.

**Required behavior:**

1. **Probe.** API gates were checked by compiling and running in the installed 27.0 SDKs, not by assumption:
   - `NSItemProvider` file, data, and object loading, and `Progress` cancellation.
   - `PasteButton(supportedContentTypes:payloadAction:)` on iOS and macOS, and `onPasteCommand`.
   - `fileImporter` and `containerURL(forSecurityApplicationGroupIdentifier:)`.
   - The share-sheet name. The share sheet lists the extension under its app's name, "Native Lab", not its own display name.
2. **Kinds.** URL, text, image, and movie are accepted. A file reference is accepted only from the host's paste; the extension refuses one.
3. **Bounded copy.** A file-backed provider's file is size-checked and cloned inside its completion handler, while the URL is still valid. Text is read as bytes and refused if it is not valid UTF-8.
4. **Durable entry.** Each attachment is written to the CORE-006 `StagingArea` with one exclusive rename, with its origin beside it. The extension then waits for Done; it never opens the store.
5. **Host review.** The host validates each import again when it lists it and again when it adopts it, then adopts it with the person's grant.
6. **Deterministic tests.** They cover:
   - the domain operation and cancellation;
   - invalid input: malformed, oversized, unsupported, hostile names, forged origins, and linked origin files;
   - duplicates;
   - the unavailable path: a folder that refuses the other surface, a build without an App Group, and a demo collection as the destination.

**Evidence:** the LAB-007-A rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md).
- The simulator runs used a throwaway UI-test harness in a copy of this branch, which is not committed.
- They ran on a new iPhone 17 Pro simulator on iOS 27.0, which was deleted afterwards.
- The shared image was an original synthetic PNG made for the run, and the link was `https://example.com/`.
- Screenshots were kept outside the repository.

**Blocked, not failed:** the share extension and App Group staging on a device.
- A free Personal Team cannot sign App Groups, so `LabPhone-Surfaces` cannot be installed on the owner's iPhone.
- The paste and file-picker fallback in `LabPhone-Core` needs no App Group and is the device path today.

**Not run:**

- Any physical device. Only the integrator installs to devices.
- A real cloud-backed (iCloud Photos or iCloud Drive) download being cancelled.
- Drag and drop onto the Mac inbox, and a Finder copy. The pasteboard file reference came from a helper, not the Finder.
- A Mac share extension, which is not built.
- VoiceOver speech, iPad layouts, a 26-SDK compile, and the Store lane manifest.

**Known limitations:**

- Images, movies, and files stage and validate but cannot be added until the domain has an attachment entity. The inbox says so.
- Text over 2,000 characters cannot become an item note.
- The Mac file picker needs `com.apple.security.files.user-selected.read-only`, which CoreLocal does not carry. AppKit logged "Unable to display open panel: your app is missing the User Selected File Read app sandbox entitlement". Choose Files is disabled on the Mac until that policy changes.
- Receipts are listed for the session only, as in CORE-005.
- Two SystemSurfaces builds with the same `LAB_BUNDLE_PREFIX` share one App Group, so a simulator holds one share inbox per prefix.

**Next dependency-ready ticket:** LAB-007-B (qualification). It needs this ticket, and CORE-007, CORE-009, and CORE-010, all done.
