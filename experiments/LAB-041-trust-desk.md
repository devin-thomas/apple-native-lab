---
id: "LAB-041"
title: "Trust Desk"
state: "implemented"
milestone: "M2"
category: "Security"
depends_on: ["LAB-001"]
source_review: "2026-09-29"
---

# LAB-041 — Trust Desk

## The moment

Authorize a sensitive local action and inspect how a passkey flow differs from just unlocking an app.

## Scope and native leverage

**Hosts:** iPhone, iPad, Mac; passkey service is optional.

**Primary APIs:** Keychain, LocalAuthentication, AuthenticationServices. API names are implementation leads; exact installed signatures and availability require a compile/probe.

**Domain types:** AuthorizationGrant, CredentialReference. These are proposed lab-owned types, not undocumented Apple symbols.

## Interaction contract

1. Protect a selected operation with local authorization
2. Store secrets only in scoped Keychain records
3. Model passkey registration/authentication against a fixture server
4. Expire and revoke grants

The first run uses original fixtures. Keep the underlying operation independent of the presentation and preserve its receipt. Offer a Reset Demo action that removes only experiment-owned fixture state. A sensitive side effect requires a separate explicit action; entering the experiment does not grant permission.

## Acceptance and proof

- [ ] A display-name change cannot change identity.
- [ ] Biometric failure retains a non-destructive recovery path.
- [ ] Passkeys are never misrepresented as exportable app secrets.
- [ ] The declared fallback completes a meaningful version of the interaction.
- [ ] Essential actions remain available through the platform's assistive and alternate-input paths.
- [ ] Actual device/OS/permission and adapter-path evidence is recorded; untested combinations remain unverified.

## Hardware, lifecycle, and boundary

LocalAuthentication is not remote account authentication. Production passkeys require a relying party and domain configuration.

Do not infer readiness from a product name. Resolve OS/API availability, current hardware capability, required assets, authorization, account/entitlement, and the experiment's verification state separately. Isolate any new permission or optional target from CoreLocal.

## Fallback

Local authorization and a clearly labeled passkey protocol simulation.

A fixture replay is labeled as a replay. It can prove the domain/UI contract but not the physical sensor, network, system surface, or external service.

## Build ownership

Proposed module: `Packages/LabFeatures/trust-desk/`, with native adapters only in supported hosts/extensions. Shared operations and imported document structures belong in the domain/store packages rather than a view. Record any narrower module split during implementation.

Implemented split (LAB-041-A):

- `Packages/LabFeatures/Sources/TrustDesk/`: the fixture identity, `AuthorizationGrant` and `DeskGrantLedger`, the scoped secret store, local authorization, and the labeled passkey simulation. Opening the sealed record and renaming go through `TrustDeskBackend` into `OperationService`. The module depends on LabDomain and never holds the store. Watch and TV hosts do not link it.
- `Apps/Shared/TrustDesk/`: `TrustDeskSession` and `LibraryTrustDeskBackend` (reads as the app UI, commits through `LabLibrary.submit`), and the shared form. The Mac reaches it from the sidebar and View › Trust Desk (⌘0), with columns in `Apps/Mac/Window/TrustDeskColumns.swift`. The iPhone reaches it from this experiment's catalog page, with no new tab.

## Implementation notes (LAB-041-A)

Observed with Xcode 27.0 (27A266a) and the 27.0 SDKs. These are Mac and package-test facts, not a person's biometric confirmation and not a system passkey.

- `LAContext.evaluatePolicy:localizedReason:reply:` is macOS 10.10, iOS 8.0, watchOS 3.0, and unavailable on tvOS. `LAPolicy.deviceOwnerAuthentication` is iOS 9.0, macOS 10.11, watchOS 3.0, unavailable on tvOS. `interactionNotAllowed` is macOS 10.13, iOS 11.0, watchOS 4.0, unavailable on tvOS, and fails with `LAError.notInteractive` instead of a dialog. The promptless probe on this Mac did not succeed.
- `ASAuthorizationPlatformPublicKeyCredentialProvider` (`init(relyingPartyIdentifier:)`, `createCredentialRegistrationRequest`, `createCredentialAssertionRequest`) is macOS 12.0, iOS 15.0, tvOS 16.0, and unavailable on watchOS. `ASPublicKeyCredential` exposes `credentialID` and `rawClientDataJSON`, not a private key. This build does not present `ASAuthorizationController`. The passkey path is a labeled simulation against `fixture.trust-desk.invalid`.
- `SecItemAdd` with `kSecUseDataProtectionKeychain` returns `errSecMissingEntitlement` (-34018) from `swift test`, which is not a sandboxed app. The store then writes a file-keychain item, still scoped by service and account and not synchronizable; that path returned `errSecInteractionNotAllowed` (-25308) because the login keychain wanted UI. The same store, inside the sandboxed Mac host, wrote and read two services for one account without a prompt.
- An `AuthorizationGrant` is not a `CommitGrant`. Opening the sealed record is an `updateItem` through the app UI, so it produces an ordinary receipt and does not need a destructive-commit grant. The desk grant is what allows that open. It lasts 60 seconds, 300 at most, and is memory-only.

## Delivery

[Implementation ticket](../tickets/LAB-041-A.md) → [qualification ticket](../tickets/LAB-041-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S47](../docs/SOURCE_INDEX.md#s47). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
