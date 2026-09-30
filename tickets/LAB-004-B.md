---
id: "LAB-004-B"
title: "Qualify and document Surface Deck"
status: "done"
milestone: "M1"
kind: "qualification"
depends_on: ["LAB-004-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-004-B — Qualify and document Surface Deck

## Goal

Prove Surface Deck on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-004-surface-deck.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** surface-deck tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Stale widget toggles reconcile to current state; Locked-device view redacts private labels; A denied update budget leaves a correct stale indicator
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Stale widget toggles reconcile to current state.
- [ ] Locked-device view redacts private labels.
- [ ] A denied update budget leaves a correct stale indicator.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac; supported Watch surfaces.

**Unavailable path:** Main-app state deck and static widget previews.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State: LAB-004 stays `implemented`.** Nothing ran on a device: the widget, the Controls, and the App Group snapshot need a team that can sign App Groups. Five records in `evidence/LAB-004/` at 4467f62: three fixture, two simulator.

**The launch crash from LAB-004-A is closed for this build.** Three clean installs of 4467f62 in the iOS simulator, 21 launches, no crash; 9 went through Open Surface Deck, 3 of them the app's first launch after an install. A control build with the presenter moved outside the library's environment crashed on 3 of 3 launches, so the check catches this class of crash. The exact pre-fix source is not in the history.

**The run that would promote it.** With a team that can sign App Groups: install `LabPhone-Surfaces` on the iPhone, add the Demo Session widget (small and Lock Screen) and both Controls, tap the Control and the widget's toggle with the app terminated, confirm new committed `setSession` receipts with adapter `app-intent` in a read-only store copy, open the deck with Open Surface Deck, and confirm the locked Lock Screen widget hides "Changed from …" with Show Details on. Record it with `DeviceRunEvidence`.

**Acceptance.**

- [x] Stale toggles reconcile: the package, hosted, and replay-variant tests (fixture), and 4 stale widget and Control taps in the simulator, each a `conflict` receipt with no session change. Not seen on a device.
- [x] The locked view redacts private labels: fixture only. The detail is off by default; the medium and Lock Screen layouts drawn with `.privacy` and read back by text recognition lose the "Changed from" line. No locked device was used.
- [x] A denied budget leaves a correct stale indicator: fixture only, the timeline's stale entry at 1 to 168 hours and the hosted declined-reload stand-in. No system refusal was observed.
- [x] Evidence identifies toolchain, input hash, adapter, and limitations: 5 records.
- [x] The walkthrough never claims a simulation is the live integration: it opens by saying nothing ran on a device and labels every screenshot.
- [x] Only public-safe material: the export review approved 9 of 9 artifacts; the screenshots show only the app's own window, metadata removed.

**Changed:** the locked-rendering tests now run text recognition on the CPU (they failed 3 of 43 with `e5rtError` 13 when the Neural Engine was contended), `evidence/LAB-004/` (5 records), `docs/walkthroughs/LAB-004-surface-deck.md` with 3 simulator screenshots, the accessibility review's check rows, flows D1–D5 with their matrix, and a Surface Deck review (4 findings), installed-SDK ledger rows, and a note under S59. Earlier on the branch (f0def18): the showcase fixtures, LabDemo runner changes, and the SurfaceDeck and Mac host qualification, accessibility, and evidence tests.

**Commands and results:** see the LAB-004-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). `script/test.sh` and `python3 script/validate/all.py` passed at d2d8a89.

**Platforms:** Mac fixture only (no Mac widget or Control is built). iPhone simulator only; physical blocked by App Group signing. Watch and TV not applicable.

**Not run:** any physical device, including the CoreLocal deck; a real Lock Screen widget; a declined WidgetKit budget; the Action button, Shortcuts, and Siri; a Mac or Watch widget; manual VoiceOver, Voice Control, and Full Keyboard Access; iPad; a 26-SDK compile.

**Follow-ups:** the Home Screen widget exposes its state symbol as a separate "Pause" element; the revision line reads a middle dot; no Mac menu command for Start or Pause; the comment on `SurfaceDeckPresenter` and the experiment's implementation note credit the sheet's explicit library for the crash fix, when the modifier order in `LabPhoneApp` is what matters; a committed UI-test target for `LabPhone-Surfaces`.

**Next dependency-ready tickets:** CORE-012 (all six M1 qualifications are done), LAB-030-A, and LAB-043-A.
