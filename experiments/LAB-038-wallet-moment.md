---
id: "LAB-038"
title: "Wallet Moment"
state: "implemented"
milestone: "M4"
category: "Commercial"
depends_on: ["LAB-008"]
source_review: "2026-09-29"
---

# LAB-038 — Wallet Moment

## The moment

Build an original event pass with a useful update story and an explicit signing boundary.

## Scope and native leverage

**Hosts:** iPhone; Watch Wallet display is system-managed. The Mac host shows the same unsigned preview and sample event card (the declared fallback).

**Primary APIs:** Wallet passes, PassKit. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** PassDefinition, PassUpdate. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Render a pass preview without signing
2. Validate the payload and barcode
3. Use an operator-supplied signing environment for a test pass
4. Inspect updates and expiration behavior

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] No pass-signing key enters a client or repo.
- [ ] A barcode is not treated as authorization by itself.
- [ ] Expired passes have an honest state.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

Wallet passes are not payment credentials, government ID issuance, or unrestricted NFC/secure-element access.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local pass preview and sample event card.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/wallet-moment/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-038-A):

- `Packages/LabFeatures/Sources/WalletMoment/`: `PassDefinition`, `PassUpdate`, `PassBarcode`, lifecycle and unsigned `PassPreview`, `PassValidator` (including refusal of signing-key fields), `PassSigningEnvironment` (`UnavailablePassSigner`, `OperatorPassSigner`, `TestPassSigner`), `EventCardOperations` over `WalletMomentBackend`, and `SampleEvent`. Depends on LabDomain only. Does not link PassKit and never holds a pass-signing key.
- `Apps/Shared/WalletMoment/`: the session, preview card, controls, iPhone page, and catalog launch. The Mac shows the same parts in its window (`Apps/Mac/Window/WalletMomentColumns.swift`), reached from the sidebar, View › Wallet Moment (⌘9), and the catalog page.
- `Fixtures/wallet/`: the sample event pass and a hostile signing-key fixture that must be refused.

## Implementation notes (LAB-038-A)

Observed with Xcode 27.0 (27A266a) and the iOS/macOS 27.0 SDKs on research. These are compile and package-test facts, not device proof and not a live Wallet install.

- `PKPass.init(data:)`, `PKPassLibrary.isPassLibraryAvailable()`, `PKAddPassesViewController.canAddPasses`, and `PKPassTypeBarcode` are present in the iOS 27.0 PassKit headers. `PKAddPassesViewController` is iPhone-only (`TARGET_OS_IPHONE`). iOS 27 also adds archive and data-based add-passes APIs. This ticket does not link PassKit into CoreLocal; add-to-Wallet is left for qualification / FrontierOptional operator signing.
- Signing stays outside the client: `OperatorPassSigner` accepts only an explicitly injected adapter and bounds its archive output; no process or network transport ships in the module (see [ADR-015](../docs/adr/ADR-015.md)). The default path is `UnavailablePassSigner`; the unsigned preview and sample event card remain usable.
- A barcode is validated as display data only. There is no API that turns a barcode into a grant, scope, or adapter. Forbidden JSON field names include `privateKey`, `grant`, and `authorization`.
- Saving the event card commits `createCollection` / `createItem` through `OperationService` as the app UI, with a receipt. Item extras record the experiment ownership and barcode message once (write-once); updates change the title and note.

## Delivery

[Implementation ticket](../tickets/LAB-038-A.md) → [qualification ticket](../tickets/LAB-038-B.md).

**Lab dependencies:** [LAB-008](LAB-008-portable-objects.md).

**Primary-source references:** [S45](../docs/SOURCE_INDEX.md#s45). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
