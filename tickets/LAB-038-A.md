---
id: "LAB-038-A"
title: "Implement Wallet Moment"
status: "done"
milestone: "M4"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-008-B"]
---

# LAB-038-A — Implement Wallet Moment

## Goal

Build an original event pass with a useful update story and an explicit signing boundary.

## Authority and scope

Read the [governing specification](../experiments/LAB-038-wallet-moment.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** wallet-moment module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Render a pass preview without signing
3. Validate the payload and barcode
4. Use an operator-supplied signing environment for a test pass
5. Inspect updates and expiration behavior
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] No pass-signing key enters a client or repo. (`PassSigningTests`: default signer unavailable; operator seam refuses non-archive and oversized output; fixtures carry no private key; `hostile-signing-key.json` refused. No PassKit link and no key material in CoreLocal.)
- [x] A barcode is not treated as authorization by itself. (`PassPreviewAndValidationTests.barcodeIsNeverAnAuthorizationSurface`; validation treats the barcode as display data; forbidden fields include `grant` and `authorization`; saved extras store the message without issuing a grant.)
- [x] Expired passes have an honest state. (`PassPreviewAndValidationTests.lifecycleIsHonestAtEachClockPoint` and `expireUpdateMakesThePassExpiredDuringTheEvent`: upcoming / active / expired at fixed fixture clocks.)
- [x] Fallback is usable: Local pass preview and sample event card.. (`SampleEvent` + unsigned `PassPreview`; Shared and Mac UI show the preview and save the event card through `OperationService`. Package fixture path proved; host-flow verification is recorded below.)
- [x] Sensitive operations share the domain authorization/receipt path. (`EventCardOperationTests`: save and update commit through `OperationService` / `WalletMomentBackend` as app UI with receipts; cancellation between collection and item; reset archives only experiment-owned cards.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Wallet passes are not payment credentials, government ID issuance, or unrestricted NFC/secure-element access.

**Research:** [S45](../docs/SOURCE_INDEX.md#s45).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State claimed: implemented.** Package tests prove the domain contract, signing boundary, and receipt path on research. Nothing is device-verified, and no `.pkpass` was added to Wallet. The branch is `ticket/LAB-038-A`; integration is pending.

**The moment.** An original Harbor Lantern Festival event pass: unsigned preview, barcode validation (display only), honest upcoming/active/expired lifecycle, seat-update story, and an operator-supplied signing seam that never embeds a key. Saving the sample event card commits through `OperationService` as the app UI with a receipt.

**Changed:**

- `Packages/LabFeatures/Package.swift`: the `WalletMoment` product and target (LabDomain only) and `WalletMomentTests`.
- `Packages/LabFeatures/Sources/WalletMoment/` (new): definition/update/barcode, lifecycle and preview, validator, signing environments, event-card operations, backend, sample event.
- `Packages/LabFeatures/Tests/WalletMomentTests/` (new): 24 tests in 3 suites.
- `Fixtures/wallet/` (new): sample event pass and hostile signing-key fixture.
- `Apps/Shared/WalletMoment/` (new): session, views, page, catalog launch.
- `Apps/Mac/Window/WalletMomentColumns.swift` and `Tests/LabMacTests/WalletMomentHostTests.swift` (new).
- Shared hooks (one case each): `SidebarDestination.walletMoment`, `MainWindowState.wallet`, `MainWindow` columns and search prompt, `SidebarView` row, `LabCommands` View › Wallet Moment (⌘9), `ExperimentDetailView` launch.
- `project.yml`: LabMac, LabPhone, and LabPhoneSurfaces link `WalletMoment`. Regenerated project.
- No PassKit link and no new entitlement. `Config/ProductPolicy.txt` only documents the domain-only boundary.
- `experiments/LAB-038-wallet-moment.md`: `state: implemented`, split, and implementation notes. Catalog JSON regenerated. LabCatalog tests expect 7 implemented / 41 specified.
- [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md) event-pass section; [VERIFICATION_BOUNDARIES](../docs/VERIFICATION_BOUNDARIES.md) S45 ledger; [SOURCE_INDEX](../docs/SOURCE_INDEX.md#s45) installed-SDK note; [BUILD_STATUS](../docs/BUILD_STATUS.md) rows.

**Implementation steps:**

1. **Probe.** Read PassKit headers on research (iOS/macOS 27.0). Ledger rows record symbols; PassKit is not linked.
2. **Unsigned preview.** `PassPreview` from `SampleEvent.definition`.
3. **Validate.** Payload, barcode, date order; refuse authority/signing fields.
4. **Operator signing.** Injected `OperatorPassSigner` / `UnavailablePassSigner` / `TestPassSigner`. Only doubles ran; a real signed pass requires operator credentials and is unverified. [ADR-015](../docs/adr/ADR-015.md) records the boundary.
5. **Updates and expiration.** `PassUpdate`, lifecycle at fixed clocks.
6. **Tests.** Domain ops, cancellation, invalid input, unavailable signing path.

**Evidence:** LAB-038-A rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). No `evidence/LAB-038/` device record (qualification).

**Not run:** Physical iPhone Wallet add-passes, a real operator-signed `.pkpass`, Watch Wallet display, PassKit-linked host build, assistive-technology passes by a person, iPad layouts.

**Continuation review.** Removed the unportable blocking `Process` runner; signing is an injected boundary with no bundled transport. Save retries retain stable identifiers, repeated saves do not duplicate cards, and Reset sample card archives only the session card with a host-issued grant. Added denied-actor, stale-update, duplicate-request, bounded-signing, cancellation and SQLite host-flow checks.

**Known limits.** This preview lists barcode format and display text; it does not draw a scannable barcode. Its clock is a labeled fixture replay. A session saves at most one active card; opening a new session can save another. Saved cards persist, but this ticket does not reload a prior session's pass model after relaunch. Reset sample card archives the current session card only; its empty collection remains. Global Reset Demo preserves these user-namespace cards. Item extras describe creation, while later pass updates are carried in the note. Archive envelope checks are not Apple signature verification. No live signing adapter or service is configured.

**Next dependency-ready ticket:** LAB-038-B, qualification, with operator signing and physical Wallet gates still explicit.

**Commands actually run (research via `labr`):**

- `xcodebuild -version` and PassKit header reads using `xcrun --sdk iphoneos` / `--sdk macosx`: Xcode 27.0 (27A266a); named Objective-C symbols and guards recorded in the installed-SDK ledger. Apple's linked Wallet Passes overview was also read; no PassKit symbol is used by the fallback.
- `swift test --package-path Packages/LabFeatures --filter WalletMomentTests`: 20 tests passed initially, 23 after authorization/retry/cancellation additions, and final 24 after raw-input validation correction.
- `script/generate_project.sh`: initial call failed with `XcodeGen is required`; `PATH=/opt/homebrew/bin:$PATH script/generate_project.sh` passed. Copied the generated project back with `rsync` as required. This command also regenerated the 48-entry catalog.
- `python3 script/validate/all.py`: all eight validators passed before the final evidence update; final result recorded below.
- `LAB_SIMULATOR_PREFIX="NL LAB-038-A" script/test.sh`: final result recorded below.

`git diff --check` passed locally. No build, Swift test, simulator, device install, merge or release was run on the editing Mac.

**Mac host fixture result.** `xcodebuild -project AppleNativeLab.xcodeproj -scheme LabMac-Core -derivedDataPath build/DerivedData -only-testing:LabMacTests/WalletMomentHostTests test -quiet` through `labr` passed. The final `xcresulttool get test-results summary` confirms 1 test passed, 0 failed, 0 skipped. It runs the session through `LabLibrary`, grants and receipts, and an isolated SQLite store: unavailable signing, save, repeat save without a second card or receipt, seat update, reset archive, and a new save after reset. The initial focused compile exposed redundant casts from typed errors; those are removed, and the final compile has no Wallet Moment compiler warnings. Xcode's multiple Mac destination/provisioning diagnostics are environment output, not a source error. This is automated fixture-host evidence, not a person's keyboard/VoiceOver pass.

**First full-gate attempt.** It waited for simulator slots and a research maintenance quiet window, then exited 2 in the shared runner before `script/test.sh` began: `labr-slot.sh: line 29: syntax error near unexpected token fi`. No full-gate test is credited to that attempt. The helper was not modified; the same gate was resubmitted through `labr`.

**First running full gate.** Exit 65 at the iPhone simulator launch, before its smoke tests: `Simulator device failed to launch org.example.lab038a.nativelab. No such process.` Eight validators, 93 validator self-tests, LabSupport 97, LabDomain 156, LabStore 44, LabStaging 40, LabDemo 119, LabFeatures 369 (including Wallet Moment 24) and Mac hosted tests passed. Share Ingress's two existing known issues were reported (cross-surface duplicate refused as identifier conflict; same-second ordering by random batch ID). The iPhone build completed; Watch, TV and the release manifest were not reached. No shared simulator was erased or modified. The script-owned simulator was cleaned up by the script; a fresh-simulator full-gate retry was submitted.

**Final four-platform gate.** `LAB_SIMULATOR_PREFIX="NL LAB-038-A" script/test.sh` passed on the fresh-simulator retry at `bbe3c26-dirty` (the implementation commit plus completion-document changes), Xcode 27.0 (27A266a). Eight validators and 93 validator self-tests passed; package counts were LabSupport 97, LabDomain 156, LabStore 44, LabStaging 40, LabDemo 119, LabFeatures 369, including all 24 Wallet Moment tests. The two existing Share Ingress known issues remained. Latest `xcresulttool get test-results summary` results: Mac 133 total (130 passed, 2 skipped, 1 expected failure); iPhone 4/4 on iOS 27.0 (24A434); Watch 115/115 on watchOS 27.0 (24R362); TV 116/116 on tvOS 27.0 (24J360), including remote focus. These are host/fixture and simulator checks, not physical Wallet checks. The release manifest built CoreLocal, SystemSurfaces and Companions within policy; CloudOptional and FrontierOptional have no targets and were skipped. The script cleaned up its own three simulators.

**Acceptance mapping.** `PassSigningTests` proves default unavailability, no key input, non-archive/oversized refusal and labeled doubles; `PassPreviewAndValidationTests` proves display-only barcode validation, refused authority fields and exact lifecycle boundaries; `EventCardOperationTests` proves authorized receipts, cancellation, denied actors, stale revisions, duplicate receipt replay and reset confinement. All ran in the final 24-test package pass and full gate. `WalletMomentHostTests` proves the fallback save/update/reset interaction through the real host's isolated SQLite store (focused 1/1 pass and full Mac gate). Actual signing and Wallet installation remain unverified, as does assistive-technology use by a person. No 26-SDK compile was run.

**SDK correction.** The ledger names the observed Objective-C `initWithData:error:` rather than inventing a Swift error-parameter spelling. `TARGET_OS_IPHONE` is recorded as the header guard, not as a claim that the controller is limited to iPhone hardware.

**Final record validation.** `python3 script/validate/all.py` through `labr` passed all eight validators after the completion records and evidence rows were updated. `git diff --check` passed.
