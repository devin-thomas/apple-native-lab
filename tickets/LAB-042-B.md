---
id: "LAB-042-B"
title: "Qualify and document Desktop Native Power"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-042-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-042-B — Qualify and document Desktop Native Power

## Goal

Prove Desktop Native Power on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-042-desktop-native-power.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** desktop-native-power tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Every gesture-only action has a discoverable alternate path; Closing a window does not destroy its document; No arbitrary shell text is executed from an intent
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Every gesture-only action has a discoverable alternate path. (`CommandCatalogTests` and the running Mac menu inspection; the hosted palette exposes all seven command titles and Close. No manual keyboard or pointer pass.)
- [x] Closing a window does not destroy its document. (Package station and hosted session close handlers; the SQLite item and receipt survive close, reload, and reset. Native document-scene close remains unverified.)
- [x] No arbitrary shell text is executed from an intent. (Package shell-admission tests, hosted refusal without a receipt, typed two-case intent enum, and source review. The intent runner commits as App Intent; system resolution/authentication was not run.)
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations. (Four records in `evidence/LAB-042/`; the bundled note is 107 bytes, SHA-256 `eb879ad9533a76c9d064ad4ef44634ec87a7164d06c4609271f3801fd4abe50e`.)
- [x] The walkthrough never claims a simulation is the live integration. (Static review; package, hosted, system, and manual paths are distinguished.)
- [x] Only approved original/public-safe material enters screenshots and exports. (Publication review: original bundled/test-authored fixture text and source hashes only. No screenshot, video, user-document export, or raw database/result bundle was collected for publication.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Mac only.

**Unavailable path:** Standard menu command and file import.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-042 stays `implemented`.** Qualification covers package contracts and Mac hosted adapters, persistence, menus, and an off-screen palette accessibility tree. It does not promote the native document scene, system Services delivery, file dialog, system intent path, or manual accessibility. No physical mobile device took part.

**Evidence:** four records in [evidence/LAB-042](../evidence/LAB-042/): package contract, hosted replay (23 observations), menu/palette/fresh-store intent checks, and static rights/privacy/accessibility review. The package record names e35785c; the attached replay names aa899c4; the four-test surface run names 6c5167d-dirty (the controller harness committed as dfb8d01); the unchanged app sources reviewed statically name 37d225c. The fixture hash agrees across the package resource and hosted preview/file path.

**Cases:** cancellation before commit, cancelled file-picker result, empty/invalid/oversized text, denied model commits, unavailable storage/link, duplicate file/menu/intent imports, a stale private route, fixture reset, global Reset Demo, and reload. A file import is distinct from a script-origin import; repeating one origin/privacy/text adds no item or receipt. Four imported user notes survive global Reset Demo. The Services handler reads a dedicated test pasteboard, not personal selected text.

**Changed:** `Tests/LabMacTests/DesktopPowerQualificationHostTests.swift` (4 tests); `evidence/LAB-042/` (4 records); the [walkthrough](../docs/walkthroughs/LAB-042-desktop-native-power.md); the experiment's qualification notes; SDK ledger; accessibility review flows DP1–DP5 and not-run manual matrix; BUILD_STATUS evidence rows. No app/domain implementation, shared host hook, package dependency, project setting, entitlement, or fixture changed. No project regeneration. The catalog generator ran; the front matter/state is unchanged and the catalog remains current.

**Commands and results:** all builds/tests through `labr` on the development Mac. Package filter `DesktopStationTests|CommandCatalogTests|ScriptAdmissionTests`: 24 passed in 3 suites. Mac `-only-testing:LabMacTests/DesktopPowerQualificationHostTests`: final v8 result bundle has 4 executed/passed, zero failed/skipped/expected failures. `xcodebuild -version`, `sw_vers`, `swift --version`: Xcode 27.0 (27A266a), macOS 27.0 (26A425), Swift 6.4.0. Resolved AppKit SDK header: `NSApplication.h:549`, nullable strong `id servicesProvider`; Headers resolves to Versions/C. `python3 script/generate_catalog.py` and `python3 script/validate/all.py`: 8/8 validators passed at that run. `git diff --check` passed locally. `LAB_SIMULATOR_PREFIX="NL LAB-042-B" script/test.sh` at dfb8d01-dirty passed with exit 0 and “All automated checks passed”: packages, Mac hosted tests, iPhone/Watch/TV simulator tests, and CoreLocal/SystemSurfaces/Companions release profiles. CloudOptional and FrontierOptional were skipped because neither has an attached scheme. The first iPhone simulator failed to launch before tests; the script’s single retry on a fresh simulator passed. Every ticket-created simulator was deleted by the script. No LAB-032 failure occurred, so no render-test retry or source patch was needed. Research pruned the build cache after completion; the full gate’s raw log/result bundles and per-host counts were not retained. The console result and the four publication-safe qualification records are the retained evidence. Final `python3 script/validate/all.py` passed all 8 checks with 58 valid evidence records after the ticket was marked done and the completion/evidence documents were in place.

**Probe corrections:** an initial test could not access the internal fixture helper; it now reads through the public preview API. Bare NSHostingView palette probes exposed unnamed outline rows; the final NSHostingController/NSWindow harness reads legacy attributes with getter fallback and passes. A method-level filter selected zero tests and proves nothing. The final off-screen host emitted recoverable toolbar constraint warnings, not a visual-layout qualification. Initial SDK `rg` was unavailable, and a guessed Versions/A path was absent; the resolved Versions/C header was read.

**Open findings:** the document scene never forwards native close to the station (route counts can be stale); repeated ordinary restore adds routes; menu-bar Open does not select the desktop destination; file cancellation reports invalid text; later Services failures cannot use the original synchronous error pointer; the file handler reads the entire file in a detached task before size validation, with no demonstrated in-flight read cancellation; private rows contain a middle dot, and session results lack explicit announcements. Private notes are not encrypted and their titles remain listed. These are documented current behaviors, not fixes.

**Not run:** native document-window open/close and relaunch interaction, system Services discovery/delivery from another app, the file panel, menu-bar interaction, actual command keypresses, Shortcuts/Siri/system intent authentication or parameter resolution, manual VoiceOver/Voice Control/Full Keyboard Access, large text/contrast/focus/motion settings, physical mobile devices, and a 26-SDK compile. Mac only is the experiment's declared surface; other host smoke checks are compatibility gates, not Desktop Native Power qualification.

**Next dependency-ready ticket:** LAB-043-B (LAB-043-A and CORE-007/009/010 are done in this checkout).
