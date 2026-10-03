---
id: "LAB-039"
title: "Tiny Doorway"
state: "implemented"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-001", "LAB-008"]
source_review: "2026-09-29"
---

# LAB-039 — Tiny Doorway

## The moment

Scan a code or open a link and arrive at one tightly scoped native action instead of a giant onboarding funnel.

## Scope and native leverage

**Hosts:** iPhone with optional App Clip; universal-link fallback elsewhere.

**Primary APIs:** App Clips, associated domains, universal links. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** InvocationContext, SignedLinkProposal. These are lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Use an original local demo action
2. Validate domain/path and untrusted parameters
3. Offer a minimal App Clip target after setup
4. Hand off confirmed state to the full app when supported

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Visits action that removes only experiment-owned visit markers. A sensitive side effect requires a separate explicit Confirm Visit action; entering the experiment or validating a link does not grant permission.

## Acceptance and proof

- [x] Malformed links cannot execute privileged actions. (`ValidationTests`, `Fixtures/LAB-039/links.json`: wrong hosts, privileged paths and query keys, unknown items, unsupported schemes, and credentials are refused before any store write. Confirm still goes through `DoorwayAction.visitOperation` → `OperationService`.)
- [x] Offline invocation has an explained fallback. (`ValidationTests.offlineBlocksHTTPSButNotDeepLinks`: offline https refuses with `DoorwayFallback.offlineExplanation`; `nativelab://` deep links still validate.)
- [x] No public hosting dependency is required for core build. (https fixtures use the fictional host `doorway.nativelab.example`; nothing is fetched. CoreLocal links no AppClip framework and declares no associated domains.)
- [x] The declared fallback completes a meaningful version of the interaction. (Local information page copy and full-app deep link fixtures open a reviewable visit; Confirm Visit commits through the receipt path. App Clip remains `DoorwayClipStatus.notConfigured` until FrontierOptional setup.)
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths. (Not run as a person pass; standard controls only.)
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified. (Package tests and CoreLocal compile only; no App Clip invocation, no physical device, no associated domains.)

## Hardware, lifecycle, and boundary

App Clip invocation needs deployment configuration; a custom URL scheme alone is not equivalent. This build keeps the App Clip path explained and unavailable in CoreLocal (`DoorwayClipStatus.notConfigured`). A FrontierOptional App Clip target, associated domains, and AASA hosting remain external gates.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Web information page or full-app deep link, with no forced installation promise.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

**Module:** `Packages/LabFeatures/Sources/TinyDoorway/` (product `TinyDoorway`), depending on LabDomain only. Host adapters in `Apps/Shared/TinyDoorway/` and `Apps/Mac/Window/TinyDoorwayColumns.swift`. Fixtures in `Fixtures/LAB-039/`.

No App Clip executable is embedded in CoreLocal. The same validator accepts the App Clip URL shape; `InvocationContext.source == .appClip` refuses while the clip target is not configured.

## Implementation notes

**Installed SDK (iOS 27.0, Xcode 27.0).** `AppClip.framework` ships `APActivationPayload` (`URL`, `confirmAcquiredInRegion:completionHandler:`), `APActivationPayloadErrorCodeDisallowed` / `DoesNotMatch`, and `NSUserActivity.appClipActivationPayload` (iOS 14.0). CoreLocal does not link the framework. Associated domains and an App Clip target stay FrontierOptional.

**Demo action.** A visit appends `Visited via Tiny Doorway.` to one allowlisted demo sample's note via `updateItem` at the revision the person saw. Confirm is separate from validation. Reset Visits strips only that marker. Malformed or privileged-looking links never produce an operation.

**Sealed proposal.** `SignedLinkProposal` has no public initializer; `DoorwayValidator` builds it with a `ContentDigest` seal over action, item, channel, and canonical URL. It is not an Apple code signature and cannot mint a grant.

## Delivery

[Implementation ticket](../tickets/LAB-039-A.md) → [qualification ticket](../tickets/LAB-039-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md), [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S52](../docs/SOURCE_INDEX.md#s52). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.

Mac shortcut: ⌃⌥⌘1 opens Tiny Doorway.
