---
id: "LAB-016-B"
title: "Qualify and document Pick Up Here"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-016-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-016-B — Qualify and document Pick Up Here

## Goal

Prove Pick Up Here on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-016-pick-up-here.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** pick-up-here tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Missing document prompts import instead of empty success; Revoked access does not reveal old content; A changed document clamps the saved position safely
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Missing document prompts import instead of empty success.
- [ ] Revoked access does not reveal old content.
- [ ] A changed document clamps the saved position safely.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac.

**Unavailable path:** Copy an explicit continuation link or document.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-016 stays `implemented`.** Package, Mac-host, and iPhone-simulator qualification of the explicit-document fallback use original fixtures. No two-device Handoff was run. A system delivery result is still required before promoting the live adapter.

**Acceptance.**

- [x] Missing document prompts import instead of empty success: `ResumeTests.aMissingDocumentPromptsImportInsteadOfSucceeding` and `FallbackTests.handoffCanStayOffAndTheCopiedDocumentStillImports`, in the 17-test package run. No revealed text and no empty success.
- [x] Revoked access does not reveal old content: `revokedAccessDoesNotReadOrRevealTheDraft`, `preparingARevokedDraftReturnsNoDocument`, and `anActorWithoutReadPermissionRevealsNothing`, in that run. Window-local revocation is a demonstration, not a platform file-permission change.
- [x] A changed document clamps the saved position safely: `aShorterNewerDraftClampsTheSavedPosition` moves section 1 to 0 in the newer shorter copy; `aNewerDraftKeepsAPositionThatStillExists` retains a valid section.
- [x] Evidence identifies toolchain, input hash, adapter, and limitations: [qualification record](../evidence/LAB-016/pick-up-here-qualification.json).
- [x] The [walkthrough](../docs/walkthroughs/LAB-016-pick-up-here.md) labels fixture replay and unverified system delivery explicitly (static review).
- [x] Only original/public-safe material: the record names the original draft hash and test sentinel; no screenshots or exported user documents were produced.

**Failures and recovery:** the package run also proves denied reads and model-tool import, cancellation before reading, unavailable storage, wrong activity type, extra-field links and activities, malformed documents, and duplicate import. The copied-document fallback works with Handoff disabled and commits through OperationService as appUI. Host qualification tests add separate fresh SQLite stores, clear/reset retention, and stale/revoked session state; the Mac and iPhone simulator xcresults each confirm both passed (2 tests, 0 failures in each qualification suite).

**Changed:** two qualification tests in each of the Mac and phone hosts; two evidence records (fixture and simulator); the walkthrough; static accessibility findings; the installed-SDK ledger, S60, and the experiment note; BUILD_STATUS evidence rows; this ticket. No production source, host hook, target, package, entitlement, or `project.yml` change. The catalog state remains unchanged, so no regeneration was needed.

**Source correction:** the installed macOS SDK declares `becomeCurrent` without a member availability annotation; it follows the class floor, rather than the later availability of `resignCurrent`. The default build already meets both floors. No behavior or support decision changed.

**Commands:** all builds and tests ran through `labr`. `script/toolchain_report.sh` reported Xcode 27.0 (27A266a), Swift 6.4, SDK family 27.0, macOS 27.0 (26A425), Apple M5 Max. Installed-header `grep` and focused `sed` confirmed the API/Team-ID contract. `swift test --package-path Packages/LabFeatures --filter PickUpHereTests` passed 17 tests. The Mac hosted qualification xcresult reports Passed (2 tests, 0 failed). The queued command’s SSH call was interrupted during resubmission; its result bundle completed successfully, and the redundant queued replacement was cancelled. `python3 script/validate/all.py` passed all 8 validators. `LAB_SIMULATOR_PREFIX="NL LAB-016-B" script/test.sh` passed validators, 93 self-tests, all packages and Mac tests, then exited 65 on unrelated phone render-report and speech-crash failures. Both Pick Up Here simulator tests passed; the overall phone stage had 12 passes and 2 failures. Separately, a temporary driver created/deleted fresh simulators and ran `xcodebuild ... -scheme LabWatch/LabTV ... test -quiet` (115/181 passed), a speech-only retry (1 passed), and `python3 script/build_manifest.py` (CoreLocal, SystemSurfaces, Companions passed; CloudOptional/FrontierOptional skipped). The attempted render leaf filter in that driver matched no test, so it is not claimed as a render retry; the one actual suite-level render retry passed 3 tests, 0 failures, on a fresh iPhone simulator. No LAB-032 or speech source was changed. Temporary drivers are not part of the change. See the LAB-016-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md) for final host/gate results.

**Not run:** physical iPhone/iPad; two-device Handoff; clipboard transfer between devices; system URL dispatch/universal links; manual VoiceOver, Voice Control, Full Keyboard Access, large text/reduced motion and iPad layout; 26-SDK compile. Watch/TV have no Pick Up Here surface. A continued activity still does not navigate the phone to this screen automatically. Clear Continuation and Reset Demo retain imported drafts. No account, network, recording, publication, or release action was performed.

**Owner gate:** a future owner-run same-Team-ID Mac/iPhone Handoff should record the sending hint, missing-document prompt, explicit import, selected section, and disabled/revoked cases with DeviceRunEvidence. Manual assistive-technology passes also remain open.

**Next dependency-ready ticket:** LAB-017-B (LAB-017-A and CORE-007/009/010 are done).
