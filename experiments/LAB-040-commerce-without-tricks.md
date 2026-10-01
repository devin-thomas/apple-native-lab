---
id: "LAB-040"
title: "Commerce Without Tricks"
state: "implemented"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-040 — Commerce Without Tricks

## The moment

Exercise buy, restore, refund, pending approval, and offline entitlement states using test products.

## Scope and native leverage

**Hosts:** StoreKit-supported iPhone/iPad/Mac/TV targets independently.

**Primary APIs:** StoreKit 2, StoreKit configuration tests. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** PurchaseState, VerifiedEntitlement. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Start exclusively with local StoreKit configuration
2. Present truthful product names and terms
3. Verify transaction state before entitlement
4. Exercise restore and revocation

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No button in the default build creates a real charge.
- [ ] Unverified transactions grant nothing.
- [ ] Restoration does not require a private developer account.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

The lab itself stays free; shipping commerce requires current policy review and appropriate product classification.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local transaction-state simulator.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/commerce-without-tricks/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-040-A):

- `Packages/LabFeatures/Sources/CommerceWithoutTricks/`: local product fixtures (`CommerceFixture`), `PurchaseState`, `VerifiedEntitlement` (only after verification), `TransactionStateSimulator` (the declared fallback), and `CommerceDesk` / `CommerceBackend`. Entitlement grants commit as `createItem` / `updateItem` through `OperationService`. StoreKit is not linked. Watch and TV hosts do not link the module.
- `Apps/Shared/CommerceWithoutTricks/`: `CommerceSession` and `LibraryCommerceBackend` (commits through `LabLibrary.submit`), and the shared form. The Mac reaches it from the sidebar and View › Commerce Without Tricks (⌃⌘9), with columns in `Apps/Mac/Window/CommerceColumns.swift`. The iPhone reaches it from this experiment's catalog page, with no new tab.
- `Fixtures/LAB-040/`: original `Commerce.storekit` configuration, a developer-only loader probe, and fixture instructions. The configuration is not enabled in any default scheme.

## Implementation notes (LAB-040-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs. Package tests prove the fallback; native host verification is recorded in the ticket. These are fixture facts, not a live StoreKit Testing run and not a device purchase.

- `Product.purchase(options:) async throws -> Product.PurchaseResult` is in the installed macOS 27.0 SDK (`PurchaseResult`: `.success(VerificationResult<Transaction>)`, `.userCancelled`, `.pending`). `VerificationResult` is `.verified` / `.unverified`. `Transaction.updates`, `currentEntitlements`, `finish()`, `revocationDate`, and `revocationReason` are present. Declared availability for the core types is below the lab's 26.0 floor.
- This build does not import or link StoreKit. The default path is `TransactionStateSimulator` over the local product fixtures, so no button can call `Product.purchase` against a real storefront. `CommerceWithoutTricks.createsRealCharge` is `false`.
- An unverified simulated transaction never produces a `VerifiedEntitlement` and never writes the store. Pending approval waits for an explicit approve. Offline keeps prior verified entitlements readable and refuses new purchases and restores. Restore reads local history only.

## Delivery

[Implementation ticket](../tickets/LAB-040-A.md) → [qualification ticket](../tickets/LAB-040-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S46](../docs/SOURCE_INDEX.md#s46). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.

The fallback-first behavior, session lifetime, bounded requests, and per-product restore/reset commits are recorded in [ADR-018](../docs/adr/ADR-018.md). The fixture configuration is developer-only; a configuration-loader run is distinct from StoreKit transaction testing.

Only the fallback is implemented here; no StoreKit-backed purchase adapter exists. The developer-only configuration probe compiled, but the local StoreKitTest service refused configuration (`SKServiceErrorDomain` code 2, underlying `SKInternalErrorDomain` code 4). Application-hosted StoreKit Testing and real transaction verification remain unrun.
