---
id: "LAB-043-B"
title: "Qualify and document Respectful Attention"
status: "done"
milestone: "M3"
kind: "qualification"
depends_on: ["LAB-043-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-043-B — Qualify and document Respectful Attention

## Goal

Prove Respectful Attention on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-043-respectful-attention.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** respectful-attention tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Denied permissions do not trigger repeated prompts; Timezone changes retain intended date semantics; Cancel removes only lab-owned schedules
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

The executable checks below are fixture and hosted-model evidence. Live permission dialogs, system delivery, and manual accessibility remain unverified.

- [x] Denied permissions do not trigger repeated prompts.
- [x] Timezone changes retain intended date semantics.
- [x] Cancel removes only lab-owned schedules.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone primary; supported Mac/Watch behavior separate.

**Unavailable path:** In-app agenda and timers visible while foregrounded.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-043 stays `implemented`.** The qualification uses original fixture input, fresh SQLite stores/defaults, a recording system adapter, and CoreLocal's unavailable adapter. No physical device, real alert, system Focus, or manual accessibility pass was used. Live SystemSurfaces behavior remains unverified.

**Acceptance evidence:**

- Denial: 13 feature tests include denied/dismissed prompt gates. The Mac hosted denial replay counts one permission request across retry and model recreation; a denied alarm remains on the agenda with zero system schedules.
- Time zones: 9 domain tests and 13 feature tests preserve the stored Chicago instant/label under Tokyo and New York device zones. Notification components keep their explicit zone; March 7/8 at 9 AM differ by 82,800 seconds; nonexistent March 8 at 2:30 AM is refused. Mac agenda alarm countdown is 27,000 seconds at the injected 8 AM instant. These are calendar fixtures, not measured delivery.
- Cancel scope: package mixed-ID/recording tests and the hosted recording adapter keep foreign sentinels. The host passes exactly its three lab IDs. No real Clock or foreign-app schedule was accessed.
- Provenance: records in `evidence/LAB-043/` name the toolchain, source revision, source/fixture hashes, adapter path, actual outcomes, and limitations. Source-only review is separate from executable fixtures and simulator launch failures.
- Walkthrough: `docs/walkthroughs/LAB-043-respectful-attention.md` distinguishes the foreground agenda, recording adapters, system integration, and owner-run gates.
- Publication: only original neutral fixture text, test source, metadata evidence, and prose. No screenshots, recordings, or media exports are included. No real alerts, private imports, or accounts were used.

**Separate remaining checks:** after the stopped full gate, explicitly booted simulator smoke checks passed iPhone 13/13, Watch 115/115, and TV 181/181. The Source-lane release manifest built CoreLocal, SystemSurfaces, and Companions and passed product policy; CloudOptional/FrontierOptional were skipped (no attached scheme). The command exited 0 and deleted only its created simulators. These checks do not change the original full-gate failure into a pass.

**Failure and reset cases:** withheld consent, invalid input, cancellation before commit, model-tool denial, stale revision, duplicate request and changed payload under a reused request ID, receipt round trip, reopened SQLite, and demo-namespace/migration checks all passed in the package runs. The clean Mac host replay stages/adopts original text with a scoped share-extension grant; cancel and reset preserve its user collection, and reset preserves the imported item exactly. Reset removes domain attention rows but does not cancel the recording system schedule; that existing live limit is recorded rather than hidden.

**Simulator fallback:** the separate explicitly booted iPhone 18 Pro / iOS 27.0 (24A434) hosted check passed 1/1. CoreLocal reports an unavailable gate with no prompt, adds all three original offers with app-UI receipts, and cancels all three domain rows. This is model replay inside the simulator host, not touch UI or live system-alert proof. The created simulator was deleted by the command’s EXIT trap.

**Source findings:** Reset Demo does not call the live system cancel adapter; scheduling discards system errors; the page always passes `systemScheduled: false`; intents commit agenda rows without calling the host system adapter; refresh does not upgrade a persisted denial after Settings grants permission. Fixed October 1 sample times are not rolling future alarms. Accessibility findings: repeated Add to Agenda labels/generic hints, no individual add/cancel Mac menu commands, and unverified result announcements. No application behavior was changed to close these findings.

**Changed:** the feature calendar test; two additional Mac hosted qualification tests; one CoreLocal iPhone hosted fallback test; evidence records; walkthrough; experiment qualification boundaries; `docs/ACCESSIBILITY_REVIEW.md`, `docs/VERIFICATION_BOUNDARIES.md`, and evidence rows in `docs/BUILD_STATUS.md`. No shared host hooks, product code, `project.yml`, entitlements, catalog metadata, or generated project changes. No decision record is needed for these tests and documentation of existing behavior.

**Commands and results:** exact build/test commands and actual outcomes are in the LAB-043-B rows of [BUILD_STATUS](../docs/BUILD_STATUS.md). Narrow package tests passed (13 feature, 9 domain, 4 SQLite). Final narrow Mac replay passed 5/5. Earlier qualification test errors were corrected: an unavailable test-only actor shorthand prevented compilation, then user-preservation assertions incorrectly read the demo-only host snapshot (4/5 passed); authorized store reads now prove preservation. The full gate passed validators, all packages, and Mac (199 total: 195 passed, 3 skipped, 1 expected failure), then stopped at two iOS runner startup failures before any experiment test. Its Watch/TV/manifest stages were not reached. The known LAB-032 Mac render flake did not occur; no unrelated source was patched.

**Not run:** physical iPhone/iPad; live AlarmKit authorization/delivery; real notification delivery and device-zone changes; Focus filter in Settings; permission recovery after Settings changes; Watch experiment behavior; pointer/touch UI walkthrough; VoiceOver, Voice Control, Full Keyboard Access, large text, contrast, reduced-motion/transparency passes; a 26-SDK compile. Owner-run live qualification needs future original offers and the separate permission/delivery/cancel-scope checks listed in the walkthrough.

**Final validation:** `python3 script/validate/all.py` through `labr` passed 8/8: catalog current (28 implemented / 20 specified), 60 evidence records valid including the six LAB-043 records. Local `git diff --check` passed. All source-input hashes were reviewed against this branch.

**Next dependency-ready ticket:** LAB-045-A (Ink Has Structure); its declared prerequisites are done. This ticket adds no live qualification or release-ready claim.
