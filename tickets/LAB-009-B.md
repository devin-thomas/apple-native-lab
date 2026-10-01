---
id: "LAB-009-B"
title: "Qualify and document Documents Everywhere"
status: "blocked"
milestone: "M4"
kind: "qualification"
depends_on: ["LAB-009-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-009-B — Qualify and document Documents Everywhere

## Goal

Prove Documents Everywhere on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-009-documents-everywhere.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** documents-everywhere tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Quick Look works without provider activation; External edits preserve document revision rules; Provider disconnect never deletes the authoritative source
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Quick Look works without provider activation.
- [ ] External edits preserve document revision rules.
- [ ] Provider disconnect never deletes the authoritative source.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** Mac and iPhone/iPad extensions separately.

**Unavailable path:** Document browser with previews; provider remains disabled until qualified.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-009 stays `implemented`; LAB-009-B is `blocked` on live-provider qualification.** The File Provider sources have no target or FrontierOptional host, and activation remains disabled. Host embedding was deferred to an owner decision by LAB-009-A. This pass records the available package and hosted-model paths without turning that deferred decision into an implementation change. System Quick Look dispatch remains unverified. Static review also found the documented `QLIsDataBasedPreview` key absent from the extension metadata; its effect on iOS has not been exercised. No physical iPhone/iPad run was assigned or attempted.

**Acceptance.**

- [ ] Quick Look works without provider activation: the shared preview builder passes with a disabled session, and the SystemSurfaces extension compiles, but no Files/Finder system preview has been observed. A shared builder is not extension-dispatch proof.
- [x] External edits preserve document revision rules: fixture model only, `RevisionRulesTests`, `ProviderSessionTests`, and `QualificationTests.editsEvictionDisconnectAndReconnectPreserveAuthority`. Metadata and content advance independently; a stale base conflicts and preserves the entire mirror. No external editor or coordinated live file ran.
- [x] Provider disconnect never deletes the authoritative source: fixture model only, catalog bytes compare unchanged across edits, eviction, repeated disconnect, and reconnect. No live domain was removed.
- [x] Evidence names measured toolchain, actual input hashes, adapters, and limitations. Hosted records are attachments from fresh stores, not invented device reports.
- [x] The walkthrough explicitly distinguishes hosted replays, shared-builder tests, the compiled extension, and the unattached provider.
- [x] Only original/public-safe material: the two bundled resources match `Fixtures/LAB-009` byte for byte. Public artifacts contain fixture hashes, metadata, and observations only; no screenshots, recordings, user store, account, or raw result bundle is published.

**Cases:** commit denial with a read/propose-only actor, deterministic pre-start cancellation with no item or pending import and a successful retry, duplicate adoption without another item or receipt, stale edit without mirror changes, duplicate connect/eviction/disconnect, malformed and newer-schema documents, escaped HTML markup, unknown sample refusal, and Reset Demo preserving both adopted user items and their canonical documents. A second package run (23/23 passed) also pins a cleanup finding: duplicate adoption leaves one staged review, and the browser has no Close Review action. No importer behavior was changed. `ProviderSession` reconnect restores original fixture revisions: it does not persist mirror edits into authority.

**Changed:** DocumentsEverywhere package qualification tests; Mac and iPhone hosted qualification tests that attach evidence; `evidence/LAB-009/`; publication-safe walkthrough; accessibility matrix and open static findings; installed-SDK/source notes; this record and BUILD_STATUS rows. Corrected the provider status message and comments/README that implied this qualification automatically activates a provider. No target, entitlement, dependency, project generation, or catalog change.

**Shared hooks:** none. The only host implementation edit is `DocumentsEverywhereSession.providerStatusMessage`, within the experiment's owned surface. The new iPhone test intentionally requires a simulator path.

**Commands and results:** all builds/tests run through `labr`; exact commands and outcomes are in the LAB-009-B rows of [BUILD_STATUS](../docs/BUILD_STATUS.md). Package filter: 23 tests in 5 suites passed. Mac filter: 4 tests passed (3 existing, 1 new). iPhone simulator hosted filter: 1 new test passed on iPhone 18 Pro, iOS 27.0 (24A434), created/deleted by the run. Four evidence records are stored, including the static blocked-gates review. Full gate failed at the unrelated Mac test `RenderSurvivesHostTests.aRenderRunsAsTheMacWorkerWithEveryStepInTheReceiptList` with `Expectation failed: model.reports[job.id]` (exit 65), after all package suites passed (LabFeatures 846, including DocumentsEverywhere 23). The script did not reach its iPhone, Watch, TV, or release-manifest steps; the separate iPhone qualification replay passed. Validators passed 8/8 with all four LAB-009 records. No unrelated code was changed. The first SDK probe failed because `rg` is absent on Research; the `grep` probe succeeded.

**Review:** static privacy/rights review passes for the stored original-fixture artifacts. Accessibility is not release-qualified: row labels retain middle dots, adoption has no Mac menu command or result announcement, the iPhone action follows a long preview, and HTML has fixed colors. All manual assistive-technology/layout passes remain not-run.

**Not run:** physical iPhone/iPad; Files/Finder extension dispatch; Mac Quick Look extension (none exists); provider target compile, domain registration/removal, materialization, external coordinated edits, live cancellation and eviction; manual VoiceOver, Voice Control, Full Keyboard Access, large text/contrast; 26-SDK compile. Watch/TV do not implement this experiment.

**Lead gate:** review the unrelated LAB-032 Mac gate failure before integration; decide a FrontierOptional host/target before provider qualification, then test the actual read-only adapter rather than the mirror model. Its `modifyItem` currently refuses every edit; the fixture revision pass cannot establish live edit acceptance. Do not enable the provider based on these records.

**Next dependency-ready ticket:** LAB-002-B (its implementation and CORE-007/009/010 are done in this checkout). No second ticket was started.
