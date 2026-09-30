---
id: "LAB-010-B"
title: "Qualify and document Typed Local Intelligence"
status: "done"
milestone: "M1"
kind: "qualification"
depends_on: ["LAB-010-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-010-B — Qualify and document Typed Local Intelligence

## Goal

Prove Typed Local Intelligence on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-010-typed-local-intelligence.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** typed-local-intelligence tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Model-unavailable paths remain usable; Malicious imported instructions cannot authorize tools; Generated-but-invalid values never reach persistence
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Model-unavailable paths remain usable.
- [ ] Malicious imported instructions cannot authorize tools.
- [ ] Generated-but-invalid values never reach persistence.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Apple-Intelligence-capable iPhone/iPad/Mac.

**Unavailable path:** Deterministic sample parser and manual editor clearly labeled as non-model paths.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State: LAB-010 stays `implemented`.** Apple's on-device model is verified on the physical development Mac only, in a test process and in the sandboxed app. The simulator run and the model-unavailable path are labeled as such, and no iPhone has run. The two physical macOS records pass `DeviceProof`, so they could support `device-verified` for the macOS model adapter, but the qualification surface includes the iPhone.

**The one run that would promote it.** On the physical iPhone 16 Pro with Apple Intelligence on and the model ready: install the current build, open Typed Local Intelligence, pick the injected note, draft with the On-Device Model (the draft should be about the Kraft card and add first-paragraph words only), and press Apply Change. A read-only copy of the store must hold exactly one new committed `app-ui` update-item receipt on the Kraft card and nothing else. Repeat with the ambiguous note, then record the run with `DeviceRunEvidence`.

**Acceptance.**

- Model-unavailable paths remain usable: `typed-intelligence-host-unavailable.json` (64 checks across 4 faked gates) and `TypedIntelligenceViewTests`. Fixture path; no real device without the model was used.
- Malicious imported instructions cannot authorize tools: fixture tests `everyWordOfTheInjectedTextIsOnlyASearch`, `theModelToolCannotCommitTheShowcasesEdit`, and `asTheModelToolAdapterTheReplayWritesNothing`, plus LAB-010-A's `HostileModelTests`. Live on the physical Mac, every draft of the injected note ignored the injection and wrote nothing (`typed-intelligence-model-mac.json`, `-mac-app.json`).
- Generated-but-invalid values never reach persistence: LAB-010-A's hostile and malformed cases, plus `anApprovalFromBeforeResetDemoCommitsOnlyAConflict`, `draftingTheSameNoteAgainAfterApplyingIsFlagged`, and `aStaleApplyRecordsAConflictAndChangesNothing`. Every live run recorded 0 writes before Apply, including the time-limit and `ExtractionFailure.other` failures.

**Changed:** `LiveModelEvidenceTests.swift` (the injected-note draft must ignore the injection; hashes of instructions and prompts; model text outside the fixture recorded only as a length and SHA-256 prefix), a new opt-in `Tests/LabMacTests/TypedIntelligenceLiveHostEvidenceTests.swift`, `TypedIntelligenceShowcaseTests.swift` (a failed extra record keeps its own result), `evidence/LAB-010/` (6 records: 5 at c2917d2 and a failure case at eb32e4f), `docs/walkthroughs/LAB-010-typed-local-intelligence.md` with 3 images, a Typed Local Intelligence review in `docs/ACCESSIBILITY_REVIEW.md` (4 findings), a Foundation Models ledger in `docs/VERIFICATION_BOUNDARIES.md`, and the typed-intelligence section of `Fixtures/showcase/README.md`. Earlier on the branch (bf1e8f7): the showcase fixtures, showcase and qualification tests, and the Mac host evidence tests.

**Commands and results:** see the LAB-010-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). `script/test.sh` and `python3 script/validate/all.py` passed at 0a78c8d.

**Platforms:** Mac passed on the physical Mac with the live model; iPhone simulator passed at c2917d2 and failed once at eb32e4f (the 30-second limit on a cold boot); physical iPhone not run. Watch and TV: `SystemLanguageModel` is unavailable on both, and the module compiles Foundation Models out there.

**Not run:** the owner's iPhone run above; a real device where the model is unavailable; the iPhone screens driven by a test; a person's review before Apply; VoiceOver, Voice Control, and Full Keyboard Access passes; a 26-family SDK compile.

**Follow-ups:** `ExtractionFailure.other` discards the underlying error's type, so the one unexplained trial failure cannot be named; add a non-text category. Measure whether the 30-second limit suits the iPhone. Accessibility findings 1 to 4 (announce draft completion, a Mac menu command and default Apply, a pinned Apply on iPhone, stale selectable diff text). A `LabPhone-Core` UI-test target so the iPhone screens can be driven by a committed test.

**Next dependency-ready tickets:** LAB-011-A, LAB-015-A, and LAB-006-A. LAB-012-A also waits on LAB-007-B; CORE-012 waits on LAB-004-B, LAB-007-B, LAB-008-B, and LAB-035-B.
