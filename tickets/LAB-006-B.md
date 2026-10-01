---
id: "LAB-006-B"
title: "Qualify and document Find the Thing"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-006-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-006-B — Qualify and document Find the Thing

## Goal

Prove Find the Thing on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-006-find-the-thing.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** find-the-thing tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Deleted private data is removed from the app index; An unsupported query returns no invented results; A generated answer cites actual record IDs
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] Deleted private data is removed from the app index.
- [x] An unsupported query returns no invented results.
- [x] A generated answer cites actual record IDs.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad, Mac.

**Unavailable path:** Lexical in-app search with the same result model.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-006 stays `implemented`.** The lexical fixture interaction ran from an empty isolated in-memory index inside the sandboxed Mac host. No physical iPhone or iPad, live Spotlight donation, Spotlight UI, Siri, or actual semantic model took part. The answer is deterministic text assembled from hit records, not generated model prose.

**Acceptance.**

- Deleted private data leaves the app index: `deletingThePrivateNoteRemovesItFromTheIndex`, `reindexKeepsADeletedFixtureOutUntilReset`, and hosted `aCleanSessionSearchesDeletesReindexesAndResets`. The host clears the old answer, a new birchbark query has no hits/citations, and reindex keeps the fixture out. This does not erase the bundled shelf detail or prove system-index deletion.
- Unsupported queries invent nothing: package `anUnsupportedQueryInventsNothing` (empty, whitespace, overlong, control-character, non-word) and the hosted `???` refusal. Unknown semantic IDs are discarded by two scripted-retriever tests; no model ran.
- Answer citations identify actual records: `cedarSearchCitesTheTwoRecordsInAStableOrder` and the hosted replay compare hits/citations and prose to indexed UUIDs ending 1002 and 1001. The default method is lexical.
- Provenance and input hash: `evidence/LAB-006/find-the-thing-host-replay.json`, emitted by the passing hosted test at `6afe19f`, includes Xcode/SDK bundle values, OS, adapter, and sorted-key corpus SHA-256 `c9d33cd5d0fbd16ab65ba82181b095820decc1504a156b3eb851bdc35a12078e`.
- Walkthrough: labels the fixture replay, idle donor, deterministic answer, unregistered internal link, retained shelf detail, and all unrun live gates.
- Rights/privacy: static review of the six original `MessyCollection` labels and original non-shelf sentinel. No personal data, screenshots, recordings, or media exports were produced. The sole JSON evidence attachment contains public-safe fixture metadata and observations.

**Failure cases:** reader deletion and model-tool index mutations are denied; pre-cancelled delete/reindex leaves state unchanged; stale lab-item revision keeps its record indexed; unavailable backend preserves the record; archive request replay retains its receipt without another revision; duplicate fixture IDs keep the first copy. `resetPreservesEveryNonShelfRecordExactly` retains the exact original non-shelf record across reindex/reset. `aFailedDonationRetainsRemovalIDsForRetry` preserves pending removals on failure, then clears them after the recording donor succeeds. No real imported document or user's store was used.

**Changed:** two qualification test files (package and Mac hosted), one fixture evidence record, the walkthrough, experiment acceptance/boundary notes, accessibility review rows, installed-SDK ledger qualification note, BUILD_STATUS rows, and this ticket. No runtime implementation, capability profile, project settings, or shared host hook changed. Catalog generation ran; its bytes did not change.

**Commands and results:** 26 narrow package tests and the focused hosted replay passed at `6afe19f`. The full `script/test.sh` passed at `6afe19f-dirty`: package tests, Mac hosted tests, iPhone/Watch/TV simulator hosts, and Release product-policy manifest. These simulator runs are compatibility smoke evidence, not a LAB-006 UI journey or system-index round trip. The LAB-006-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md) record narrow, hosted, SDK, full-gate, and validator results. Hosted test attachments were exported with `xcrun xcresulttool export attachments` and the sole LAB-006 record copied unchanged into evidence. One early combined run never started because concurrent wrapper setup reported `mv: .labr-slot.sh.new: No such file or directory`; the sequential retry passed. Initial SDK searches through framework symlinks produced no match; the Versions/A interfaces were then inspected.

**Review:** labeled controls, textual index/retrieval states, Return-to-search, and the Mac navigation shortcut were inspected in source only. Manual VoiceOver, Voice Control, Full Keyboard Access, large text, and system display settings remain `not-run`. Findings: no index-action menu shortcuts or result announcements, verbose UUID labels, and potentially offscreen iPhone actions. Deleted fixture text remains accessible through the shelf detail; do not promise erasure.

**Not run / owner gates:** physical iPhone/iPad; live IndexedEntityDonor and deletion round trip; Spotlight visibility, Siri/Shortcuts entity resolution; actual semantic retrieval; external URL opening; manual accessibility; iPad simulator layout; 26-SDK compile. A permitted owner run must explicitly donate the original opted-in records, verify visibility, delete and donate removals, and verify absence before any live-system claim. No project regeneration or device installation is needed from the lead for this change.

**Next dependency-ready ticket:** LAB-003-B (its LAB-003-A and core prerequisites are done). This qualification does not change downstream dependencies.
