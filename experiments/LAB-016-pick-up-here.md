---
id: "LAB-016"
title: "Pick Up Here"
state: "implemented"
milestone: "M2"
category: "Continuity"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-016 — Pick Up Here

## The moment

Move a draft to another device and resume at the exact selected section without pretending Handoff is file sync.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac.

**Primary APIs:** NSUserActivity, Handoff, universal-link routing. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** ContinuationToken, DocumentLocator. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Advertise a small resumable activity
2. Transfer only identifiers and position
3. Resolve or request the underlying document
4. Handle a newer revision on the destination

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Missing document prompts import instead of empty success.
- [ ] Revoked access does not reveal old content.
- [ ] A changed document clamps the saved position safely.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Handoff is a continuation hint, not guaranteed bulk transfer or instant background execution.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Copy an explicit continuation link or document.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/pick-up-here/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-016-A):

- `Packages/LabFeatures/Sources/PickUpHere/`: `DocumentLocator`, `SectionPosition`, `ContinuationToken`, the activity payload and the continuation link (identifier, revision, and section only), `ContinuationDocument` (the explicit copy), `PickUpResolver`, `ContinuationImporter`, and `HandoffActivity`. It depends on LabDomain and never holds the store. Sections are the item note split on a blank line.
- `Apps/Shared/PickUpHere/`: the session and `LibraryPickUpBackend` (reads as the app UI, import commits through `LabLibrary.submit`), the actions, and the iPhone screen. The Mac reaches it from the sidebar and View › Pick Up Here (⌥⌘1), with its columns in `Apps/Mac/Window/PickUpColumns.swift`. The iPhone reaches it from this experiment's catalog page, with no new tab.
- `Fixtures/LAB-016/`: the original sample draft. The same words are `SampleDraft` in the module.

## Implementation notes (LAB-016-A)

Observed with the macOS, iOS, watchOS, and tvOS 27.0 SDKs. These are package-test facts, not device proof, and not a Handoff delivery between two devices.

- `NSUserActivity` is declared in `Foundation.framework/Headers/NSUserActivity.h`, not in the Foundation Swift interface. The class is available on macOS 10.10, iOS 8, watchOS 2, and tvOS 9. `isEligibleForHandoff`, `requiredUserInfoKeys`, `becomeCurrent()`, and `resignCurrent()` are available on macOS 10.11, iOS 9, watchOS 3, and tvOS 10, under the 26 floor. No `LAB_SDK_27` gate. SwiftUI's `userActivity(_:isActive:_:)` and `onContinueUserActivity(_:perform:)` are iOS 14, macOS 11, tvOS 14, and watchOS 7.
- The activity type `nativelab.pick-up-here` is listed in `NSUserActivityTypes` on the Mac, iPhone, and iPhone surfaces hosts. The header says a continuation is delivered only to an app with the same developer Team ID that lists the type. No two-device handoff was run.
- The activity does not set `webpageURL`, `supportsContinuationStreams`, search, or public indexing. A web URL would ask a browser to load a page this lab does not serve. Streams would let the other side pull more than the hint. There is no associated-domains entitlement. The continuation link is `nativelab://continue` with the three hint fields, copied and pasted, not fetched.
- A missing draft returns an import prompt and no section text. Revoked access returns before the item is read. A newer, shorter draft clamps the section into range. Importing the copied document commits `createItem` through `OperationService` as the app UI. A model tool cannot commit that import.

## Delivery

[Implementation ticket](../tickets/LAB-016-A.md) → [qualification ticket](../tickets/LAB-016-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S60](../docs/SOURCE_INDEX.md#s60). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
