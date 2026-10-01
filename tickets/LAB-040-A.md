---
id: "LAB-040-A"
title: "Implement Commerce Without Tricks"
status: "done"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B"]
---

# LAB-040-A — Implement Commerce Without Tricks

## Goal

Exercise buy, restore, refund, pending approval, and offline entitlement states using test products.

## Authority and scope

Read the [governing specification](../experiments/LAB-040-commerce-without-tricks.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** commerce-without-tricks module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Start exclusively with local StoreKit configuration
3. Present truthful product names and terms
4. Verify transaction state before entitlement
5. Exercise restore and revocation
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] No button in the default build creates a real charge. (`CommerceWithoutTricks.createsRealCharge == false`; StoreKit is not linked; every purchase control is labeled as a simulation. Proved by `CommerceWithoutTricksOperationTests.noPathCreatesARealCharge` and `CommerceHostTests`.)
- [x] Unverified transactions grant nothing. (`TransactionVerification.makeEntitlement` returns nil for `.unverified`; purchase script `.unverified` leaves the store empty: `anUnverifiedTransactionGrantsNothing`, host test.)
- [x] Restoration does not require a private developer account. (Restore reads the local simulator history only; messages and notes say no Apple Account. `restoreDoesNotNeedAPrivateDeveloperAccount`, host test.)
- [x] Fallback is usable: Local transaction-state simulator. (Buy, pending approval, restore, refund, revoke, and offline all run in `TransactionStateSimulator`: `theLocalSimulatorCoversBuyRestoreRefundPendingAndOffline`. Hosted Mac path commits through `LabLibrary.submit`.)
- [x] Sensitive operations share the domain authorization/receipt path. (Verified grants are `createItem` / `updateItem` through `CommerceBackend` → `OperationService` as app UI, with receipts: `sensitiveOperationsShareTheDomainReceiptPath`, host tests.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** The lab itself stays free; shipping commerce requires current policy review and appropriate product classification.

**Research:** [S46](../docs/SOURCE_INDEX.md#s46).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

LAB-040 is `implemented` for its local fallback on Mac and iPhone. The simulator commits entitlement teaching records through the app's operation service. No default control creates a real charge. No StoreKit-backed purchase adapter exists, and nothing is device-verified. The local StoreKitTest service probe is blocked as recorded below; that does not turn its constructor assertion into a passing StoreKit test.

**Changed:**

- `Packages/LabFeatures`: `CommerceWithoutTricks` product/target, depending only on LabDomain, with typed fixture products, transaction states, verified entitlement snapshots, the actor-owned simulator, `CommerceDesk`, backend protocol, and explicit errors. Its tests are split into operations, failures, lifecycle, configuration parity, and test backends.
- `Apps/Shared/CommerceWithoutTricks/`: per-screen `CommerceSession`, `LibraryCommerceBackend`, native list/form, and catalog launch. Product search is functional on Mac; controls identify simulated purchases, approval, restoration, refunds, and revocation.
- `Apps/Mac/Window/CommerceColumns.swift`: the desk, explanation, and receipt inspector connection.
- Shared hooks: `MainWindowState` destination/restoration/session; `MainWindow` columns/search prompt; `SidebarView` row; `LabCommands` View menu (⌘9); `ExperimentDetailView` launch. No shared operation/store implementation changed.
- `project.yml` and the regenerated project: Mac, Phone, and PhoneSurfaces link the package. Watch and TV retain their smoke hosts without linking commerce. No StoreKit framework, permission, or entitlement was added to a host.
- `Fixtures/LAB-040/`: original `Commerce.storekit`, fixture instructions, and a developer-only XCTest probe/driver. No default scheme enables the configuration.
- [ADR-015](../docs/adr/ADR-015.md): fallback-first behavior, session lifetime, reset scope, and per-product commits.
- Spec/catalog state, catalog count tests, S46 source notes, installed-SDK ledger, build-status rows, and four [evidence records](../evidence/LAB-040/commerce-host-gate.json).

**Behavior and failure handling.** The simulator stages a change until its authorization-checked store operation commits. Refused approval, refund, revocation, reset, cancellation, and stale receipts preserve the last accepted entitlement. A duplicate request returns its original receipt and rechecks authorization; a different action under that ID is refused. The desk rejects reentrant changes and bounds a session to 256 request IDs. Refund/revocation discard the revoked claim's restore history, so a later failed/unverified attempt cannot resurrect it. Failed or pending attempts can retain an earlier verified grant but never grant a new one.

A recorded stale conflict renews the native session's request ID so a reviewed purchase, restore, or reset can be retried; an unrecorded refusal keeps its ID. A hosted regression first failed, then passed after this fix.

History lasts for one screen session; reopening begins a fresh simulation while lab records and receipts persist. Reset Commerce changes only its two product notes and simulator state, preserving unrelated records. It refuses a product item found outside its collection. Multi-product restore/reset commit separately: an earlier successful product remains committed if a later product fails. Preparing the collection is also a separate operation, so an empty experiment collection may remain after a refused item write.

**Implementation steps:**

1. Read the installed macOS 27.0 StoreKit interface on research: `Product.purchase(options:)`, `PurchaseResult`, `VerificationResult`, transaction updates/entitlements/finish, and revocation fields. The `confirmIn` overload is macOS 15.2 and unavailable on the other platforms. No 27-only StoreKit symbol enters an app.
2. Added the original local configuration for `lab.commerce.field-notebook` and `lab.commerce.sample-compass`. Configuration parity passes; activating its service is blocked on this standalone runner.
3. Truthful fixture names/prices/terms are visible before actions; every product is simulated, with no real charge.
4. Only verified simulated outcomes may produce a new entitlement and persist it. This is not StoreKit signature verification.
5. Buy, pending approval, restore, refund, revocation, and offline cached entitlement states run in the declared fallback.
6. Domain tests and hosted Mac tests cover the operation/receipt path and refusals. Native UI/manual accessibility qualification remains separate.

**Commands actually run on research through `labr`:**

| Command | Result |
|---|---|
| `script/toolchain_report.sh`; installed StoreKit interface/header `grep` / `sed` | Xcode 27.0 (27A266a), Swift 6.4, SDKs 27.0, macOS 27.0 (26A425), Apple M5 Max; ledger updated |
| `swift test --package-path Packages/LabFeatures --filter CommerceWithoutTricksTests` | First two compiles failed on typed closure/catch inference; fixed explicitly. Final run: 18 tests in 4 suites passed |
| `export PATH=/opt/homebrew/bin:$PATH; script/generate_project.sh` | Passed; catalog generated and project regenerated on research, then copied back with `rsync`. Project diff adds the three commerce product links |
| `Fixtures/LAB-040/check_configuration.sh` | Final driver exits 1: `SKServiceErrorDomain` code 2, underlying `SKInternalErrorDomain` code 4, while saving configuration. Earlier probes exposed missing XCTest runtime and support search paths. The driver detects service errors even when the constructor assertion passes. No purchase requested |
| `python3 script/validate/all.py` | 8/8 passed before the full gate; final documentation validation recorded in BUILD_STATUS |
| `LAB_SIMULATOR_PREFIX="NL LAB-040-A" script/test.sh` (logged with `tee build/LAB-040/full-gate.log`) | Passed at `9c50384-dirty`: validators 8/8, 93 validator self-tests; packages 97/156/44/40/119/363 (LabFeatures in 9 runs, commerce 18); Mac 134 total (131 passed, 1 expected failure, 2 skipped); iPhone 4, Watch 115, TV 116 passed; release profiles passed |
| `xcrun xcresulttool get test-results summary` / `tests` | Both CommerceHostTests cases passed: verified/unverified receipt behavior and account-free local restoration. Existing Share Ingress known issues, Mac expected failure, and skips remain unchanged |
| `xcodebuild -project AppleNativeLab.xcodeproj -scheme LabMac-Core -destination platform=macOS -derivedDataPath build/DerivedData -only-testing:LabMacTests/CommerceHostTests -collect-test-diagnostics never LAB_SOURCE_REVISION=9c50384-dirty test -quiet` | Before the fix, stale purchase retry failed (exit 65). After the fix, the selected suite of three cases passed (exit 0), including stale purchase/restore/reset recovery. Follow-up after the full gate; source committed as fedd8c0. Later xcresult inspection found no retained bundle |
| `xcodebuild -project AppleNativeLab.xcodeproj -scheme LabPhone-Core -sdk iphonesimulator -derivedDataPath build/DerivedData LAB_SOURCE_REVISION=9c50384-dirty build -quiet` | Passed (exit 0) after the retry fix; compilation only, no iPhone UI walkthrough |

**Evidence:** [domain fixtures](../evidence/LAB-040/commerce-domain-fixtures.json), [host/full gate](../evidence/LAB-040/commerce-host-gate.json), [stale recovery follow-up](../evidence/LAB-040/commerce-stale-recovery.json), [blocked StoreKit configuration](../evidence/LAB-040/commerce-storekit-configuration.json). Input hashes and source revisions distinguish package fixtures, hosted calls, and the blocked developer probe. The Source-lane manifest built CoreLocal, SystemSurfaces, and Companions; CloudOptional and FrontierOptional were skipped because no schemes exist. No StoreKit reference appears in the built-product manifest.

**Not run:** Application-hosted StoreKit Testing, live transaction verification, any StoreKit or App Store purchase, a physical device, iPad, manual VoiceOver / Voice Control / Full Keyboard Access, an iPhone commerce walkthrough, and a 26-SDK / Swift 6.2 compile. Watch/TV smoke tests passed; neither has a commerce presentation.

**Next:** [LAB-040-B](LAB-040-B.md), dependency-ready for qualification. Investigate the local StoreKit service refusal in an application-hosted test without introducing a real storefront route.
