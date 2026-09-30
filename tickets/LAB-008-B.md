---
id: "LAB-008-B"
title: "Qualify and document Portable Objects"
status: "done"
milestone: "M1"
kind: "qualification"
depends_on: ["LAB-008-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-008-B — Qualify and document Portable Objects

## Goal

Prove Portable Objects on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-008-portable-objects.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** portable-objects tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Unicode and empty optional fields round-trip; A path-traversal attachment is rejected; Reimporting one document does not duplicate stable items
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Unicode and empty optional fields round-trip.
- [ ] A path-traversal attachment is rejected.
- [ ] Reimporting one document does not duplicate stable items.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac.

**Unavailable path:** File picker and explicit export preserve the full native document.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State: LAB-008 stays `implemented`.** The Mac's Export… and Import from File… ran in the real app on the development Mac, driven by a test agent through the Accessibility API. The Files round trip ran in the iOS simulator. No person has dragged anything, and no iPhone or iPad took part.

**Review decision on the Mac record.** `portable-objects-mac-file-dialogs.json` is recorded on the physical path because the real app, AppKit's panels, and the app's container ran on the development Mac. Its limitations state that an agent drove it and that no drag ran. It is physical evidence for the Mac file-dialog adapter only; it does not stand in for a person's drag, and it promotes nothing on its own.

**The runs that would promote it.** A person drags an object between two Mac windows and to Finder, and one Files round trip runs on the physical iPhone, each recorded with `DeviceRunEvidence`.

**Acceptance.**

- [x] Unicode and empty optional fields round-trip: the package tests (8 titles × 5 note forms, empty shapes, Unicode keys) and 5 variants through two hosted stores; on the Mac and in the simulator, the sample with its combining accent, CJK, emoji, empty note, and extras. S0, M1, S1, and M2 are all 682 bytes with SHA-256 `4dfbd2a9…`, byte-identical to the bundled sample.
- [x] Path traversal is rejected: 16 unsafe paths in the package tests, and the fixture file on the Mac and in the simulator.
- [x] Reimport doesn't duplicate: `ReimportQualification`, two hosted windows, the Mac run, and the simulator run.
- [x] Evidence names toolchain, input hash, adapter, and limitations: 3 records in `evidence/LAB-008/`.
- [x] The walkthrough never claims a simulation is the live integration (static review).
- [x] Only approved original material: the screenshots show the app's own window with the original fixture, and the export review approved all 3 records as `public-fixture`.

**Cases:** denial (`anActorWithoutTheCommitPermissionCannotImport`, `aClosedReviewCanNoLongerCommit`), cancellation (`aCancelledCommitCanBeRetriedAndCommitsOnce`), stale state (`anObjectCreatedDuringTheReviewStopsTheCommit`, `aCopyArchivedDuringTheReviewIsNotChanged`, hosted `aChangeInTheLabDuringTheReviewStopsTheImport`), duplicates (`ReimportQualification`, hosted `twoWindowsImportingOneObjectCommitItOnce`), and reset (`resetDemoLeavesImportedObjectsAndTheirDocumentsAlone`, `aReviewOpenAcrossResetDemoStillImportsAsYourOwn`). Recorded as current behavior, not fixed: two reviews of the same bytes share one staged copy, so closing one withdraws the other.

**Changed:** `evidence/LAB-008/` (3 records), `docs/walkthroughs/LAB-008-portable-objects.md` with 3 simulator screenshots. Earlier on the branch (6a59e44): the PortableObjects qualification and evidence tests and the Mac host evidence and qualification tests. No showcase fixture: the replay script format has no import step, and `PortableObjectsInteractionReplay` replays the whole interaction from clean stores.

**Commands and results:** see the LAB-008-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). `script/test.sh` and `python3 script/validate/all.py` passed at ed64c53.

**Platforms:** Mac passed on the physical path, agent-driven file dialogs only. iPhone passed in the simulator only. Watch and TV not applicable.

**Not run:** any drag by a person (LAB-008-A's Finder file-promise failure stands: "Sandbox extension data required immediately … (-20)"), a physical iPhone, iPad, Share…, AirDrop and iCloud Drive arrivals, replacing a file in the simulator (saving over an existing name wrote nothing twice), VoiceOver, Voice Control, and Full Keyboard Access, and a 26-SDK compile.

**Follow-ups:** a possible Finder fix, unproven: also offer a plain file URL beside the file promise. The export card's "to Finder or Files" wording overclaims until a person's Finder drag works. Accessibility findings for the host views: rows read middle dots aloud, the Mac has no menu commands for Import from File…, Import Sample Object, or Export…, and Export… is below the fold on iPhone at the default size. A Portable Objects section in `docs/ACCESSIBILITY_REVIEW.md`, Transferable rows in the SDK ledger, and a committed UI-test target for `LabPhone-Core`.

**Next dependency-ready tickets:** LAB-009-A (Documents Everywhere), LAB-003-A, LAB-013-A, LAB-016-A, LAB-017-A, and LAB-045-A. CORE-012 still waits on LAB-004-B and LAB-007-B.
