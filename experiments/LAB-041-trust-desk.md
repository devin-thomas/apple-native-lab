---
id: "LAB-041"
title: "Trust Desk"
state: "specified"
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

## Delivery

[Implementation ticket](../tickets/LAB-041-A.md) → [qualification ticket](../tickets/LAB-041-B.md).

**Lab dependencies:** [LAB-001](LAB-001-action-atlas.md).

**Primary-source references:** [S47](../docs/SOURCE_INDEX.md#s47). A source is not device proof.

See [data contracts](../docs/DATA_CONTRACTS.md), [permission boundaries](../docs/EXTENSION_AND_PERMISSION_MATRIX.md), and [test strategy](../docs/TEST_STRATEGY.md) for shared requirements.
