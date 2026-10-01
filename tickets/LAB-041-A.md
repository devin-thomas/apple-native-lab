---
id: "LAB-041-A"
title: "Implement Trust Desk"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-041-A — Implement Trust Desk

## Goal

Authorize a sensitive local action and inspect how a passkey flow differs from just unlocking an app.

## Authority and scope

Read the [governing specification](../experiments/LAB-041-trust-desk.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** trust-desk module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Protect a selected operation with local authorization
3. Store secrets only in scoped Keychain records
4. Model passkey registration/authentication against a fixture server
5. Expire and revoke grants
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] A display-name change cannot change identity. (`TrustDeskOperationTests.aDisplayNameChangeDoesNotChangeIdentity`, `renamingDoesNotReplaceThePasskey`: the stable `DeskIdentityID` / keychain account / passkey user handle stay `04104104-1041-4041-8041-041041041041` after renames. Hosted: `TrustDeskHostTests.aFailedBiometricThenLocalConfirmationOpensThroughTheAppUI` renames to "North fixture" with the same identity and the same keychain secret.)
- [x] Biometric failure retains a non-destructive recovery path. (`aBiometricFailureKeepsALocalConfirmationPath`: scripted biometric failure leaves no grant, no secret, and no item; Confirm locally then opens through an app-UI `updateItem` receipt. Hosted: the same sequence through `LabLibrary.submit`. Promptless `LAContext` probe does not succeed and issues no grant.)
- [x] Passkeys are never misrepresented as exportable app secrets. (`aPasskeyAssertionDoesNotAuthorizeTheSealedRecord`, `authenticationBeforeRegistrationIsRefused`: `CredentialReference.isExportableAppSecret` is false; `exportPasskeyMaterial` and `copyAppSecret` on a passkey reference throw `passkeyIsNotAnAppSecret`; a passkey assertion does not open the sealed record. UI labels every step as a protocol simulation.)
- [x] Fallback is usable: Local authorization and a clearly labeled passkey protocol simulation. (Local confirmation is an explicit in-app grant labeled as not a passkey. The passkey path is the labeled simulation against `fixture.trust-desk.invalid`; it does not present `ASAuthorizationController`. Mac: View › Trust Desk (⌘0) and the catalog Open button. iPhone: catalog page NavigationLink.)
- [x] Sensitive operations share the domain authorization/receipt path. (Rename, open, and reset go through `TrustDeskBackend` → `LabLibrary.submit` → `OperationService` as the app UI. Hosted open receipt has `admitted.adapter == .appUI`. Secrets stay in the scoped keychain store and never appear in receipts or notes.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** LocalAuthentication is not remote account authentication. Production passkeys require a relying party and domain configuration.

**Research:** [S47](../docs/SOURCE_INDEX.md#s47).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-041's spec claims `implemented`. Local confirmation, the labeled passkey simulation, and the scoped keychain write ran on the Mac (package tests and the sandboxed host). No person confirmed biometry. No system passkey ceremony ran. Nothing is device-verified.

**Changed:**

- `Packages/LabFeatures`: the `TrustDesk` product and target (new), depending on LabDomain only, and `TrustDeskTests` (new): `TrustDeskOperationTests`, `KeychainSecretStoreTests`, `InstalledAuthenticationProbeTests`.
- `Packages/LabFeatures/Sources/TrustDesk/` (new): `DeskIdentity`, `AuthorizationGrant` / `DeskGrantLedger`, `SecretStore` (memory, unavailable, keychain), `LocalAuthorizer` (scripted and `DeviceOwnerAuthorizer`), `PasskeySimulation` / `PasskeyPlatformProbe`, `TrustDesk` / `TrustDeskBackend` / `TrustDeskError` / `TrustDeskFixture`.
- `Apps/Shared/TrustDesk/` (new): `TrustDeskSession`, `LibraryTrustDeskBackend`, `TrustDeskForm`, `TrustDeskScreen`, `TrustDeskLaunch`.
- `Apps/Mac/Window/TrustDeskColumns.swift` (new).
- Hooks in shared host files, one case each:
  - `MainWindowState`: destination and per-window session.
  - `MainWindow`: columns and search prompt.
  - `SidebarView`: row.
  - `LabCommands`: View › Trust Desk (⌘0).
  - `ExperimentDetailView`: Open Trust Desk.
- `project.yml` and the regenerated project (byte-identical over two runs): LabMac, LabPhone, and LabPhoneSurfaces link `TrustDesk`; Store-lane `NSFaceIDUsageDescription` for LocalAuthentication. Watch and TV do not link it.
- `Config/ProductPolicy.txt`: CoreLocal and SystemSurfaces may link LocalAuthentication, AuthenticationServices, and (iOS) Security for this desk; purpose string for Face ID.
- `Config/PurposeStrings.xcconfig`: `LAB_PURPOSE_FACE_ID`.
- `docs/DATA_CONTRACTS.md`, `docs/SOURCE_INDEX.md` (S47), `docs/VERIFICATION_BOUNDARIES.md`: Trust Desk credentials and installed-SDK ledger rows.
- `experiments/LAB-041-trust-desk.md`: `state: implemented`, the module split, and implementation notes. Catalog JSON regenerated. Catalog tests expect seven implemented experiments.
- `Tests/LabMacTests/TrustDeskHostTests.swift` (new).
- This record, and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** Installed SDK headers for `LAContext` / `LAPolicy.deviceOwnerAuthentication`, `ASAuthorizationPlatformPublicKeyCredentialProvider`, and `SecItem`. Findings are in the spec notes and the verification ledger. Promptless LA evaluation on the Mac did not succeed.
2. **Protect the open.** A live `AuthorizationGrant` (device owner or local confirmation) is required; passkey assertions do not issue one.
3. **Scoped Keychain.** Fixture secret under service `lab.trust-desk.fixture` and the identity UUID as account; not synchronizable; this-device-only when data-protection succeeds.
4. **Passkey simulation.** Registration and authentication against `fixture.trust-desk.invalid`; private material is not exportable; labeled in the UI.
5. **Expire and revoke.** Default 60 s, max 300 s, monotonic clock; revoke keeps the record and secret.
6. **Tests.** Domain operation, cancellation, invalid input, unavailable lab/keychain, expiry, revocation, and the sandboxed host path.

**Not run:** A physical device; a person succeeding or failing biometry or the device passcode; a system passkey with a real relying party; VoiceOver / Voice Control / Full Keyboard Access passes; iPad; a 26-SDK compile; Watch and TV (hosts do not link the module).

**Next:** [LAB-041-B](LAB-041-B.md) (qualification).
