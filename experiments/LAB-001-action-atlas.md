---
id: "LAB-001"
title: "Action Atlas"
state: "implemented"
milestone: "M1"
category: "System surfaces"
depends_on: []
source_review: "2026-09-29"
---

# LAB-001 — Action Atlas

## The moment

Create a collection, find an item, mutate it, and inspect the same receipt from three entry points.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; Watch adapter later.

**Primary APIs:** AppIntents, AppEntity, entity queries. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** LabItem, Collection, ActionReceipt. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Seed 12 original sample objects with stable UUIDs
2. Expose create/find/update/archive/export intents
3. Call the same operation from UI and Shortcuts
4. Show typed output and undo receipt

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] Duplicate request IDs cause one mutation.
- [ ] Missing and ambiguous entities produce recoverable errors.
- [ ] UI and intent yield identical persisted state.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

AppEntity is not arbitrary access to other apps. Domain operations remain authorization-checked.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

A normal app action browser runs without Siri or Apple Intelligence.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/action-atlas/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-001-A):

- `Packages/LabFeatures/Sources/ActionAtlas/`: the action library both entry points call (`ActionAtlasActions`), the App Intents, the `LabItemEntity` and `LabCollectionEntity` entities with their queries, the portable export format, and `ActionAtlasIntentsPackage`. It depends on LabDomain only and never holds the store.
- `Apps/Shared/ActionAtlas/`: the host backend over `LabLibrary` and `LabDataService`, the dependency registration, the host's `AppIntentsPackage`, and the in-app action browser. The Mac reaches it from the sidebar and View › Action Atlas (⌘4); iPhone has an Actions tab.

## Implementation notes (LAB-001-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs. These are compile and simulator facts, not device proof.

- App Intents in a Swift package target work in this SDK. Xcode runs `appintentsmetadataprocessor` on the package target and merges its intents, entities, queries, and enum into the host's `Metadata.appintents` once the host declares an `AppIntentsPackage` that includes the package's. Conforming the `App` type itself fails to compile under Swift 6 (main-actor isolation), so the host uses a separate struct.
- Destructive intents confirm with `requestConfirmation(conditions:actionName:dialog:)` (macOS 15, iOS 18 and later). The older `requestConfirmation(result:confirmationActionName:showPrompt:)` is deprecated in this SDK. A custom destructive action name uses `ConfirmationActionName.custom(acceptLabel:acceptAlternatives:denyLabel:denyAlternatives:destructive:)`. Cancelling throws; the intent lets that error propagate, and nothing is committed.
- Disambiguation uses `IntentParameter.requestDisambiguation(among:dialog:)`. An `EntityStringQuery` that returns several matches leaves the choice to the system.
- `supportedModes` replaces `openAppWhenRun` (deprecated in the 26 SDK); the intents keep the default background mode.
- The system confirmation is the only step that grants an intent's archive. Its `IntentConfirmation` covers exactly the confirmed operation, and the host issues the ADR-013 grant only for that. Non-destructive intent changes commit under the App Intent adapter with no grant.
- New items need one of the person's own collections, because ADR-012 keeps demo collections to the samples. It adds one step to a first run: create a collection, then an item. Editing, archiving, and exporting demo samples need no extra step.

## Delivery

[Implementation ticket](../tickets/LAB-001-A.md) → [qualification ticket](../tickets/LAB-001-B.md).

**Lab dependencies:** none beyond the core foundation.

**Primary-source references:** [S01](../docs/SOURCE_INDEX.md#s01), [S03](../docs/SOURCE_INDEX.md#s03), [S05](../docs/SOURCE_INDEX.md#s05). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
