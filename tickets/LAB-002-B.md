---
id: "LAB-002-B"
title: "Qualify and document Context Cards"
status: "done"
milestone: "M2"
kind: "qualification"
depends_on: ["LAB-002-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-002-B — Qualify and document Context Cards

## Goal

Prove Context Cards on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-002-context-cards.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** context-cards tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: A replaced onscreen item cannot mutate the previous item; A schema mismatch fails the integration gate; Siri-disabled devices retain the same decision UI
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [x] A replaced onscreen item cannot mutate the previous item.
- [x] A schema mismatch fails the integration gate.
- [x] Siri-disabled devices retain the same decision UI.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [x] The walkthrough never claims a simulation is the live integration.
- [x] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone and iPad; Mac support probed separately.

**Unavailable path:** In-app card and typed Shortcut remain complete; context resolution is explicitly unavailable.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-10-01)

**State: LAB-002 stays `implemented`.** Qualification is of the fallback. Context resolution remains unavailable by design. Two retained records: the hosted fixture at 605a95d and iPhone simulator host smoke at 317b4b1-dirty. Fixture: [context-cards-host-fallback.json](../evidence/LAB-002/context-cards-host-fallback.json). Mac Studio, macOS 27.0 (26A425), Xcode 27.0 (27A266a), SDKs 27.0. No physical device run, Siri, Shortcuts app, or system snippet.

**Acceptance.**

- [x] A replaced sample cannot mutate its predecessor: package stale checks before and during confirmation; hosted stale check; new host session prepare/replace/confirm replay. Neither sample archives and no stale-session receipt is added.
- [x] Schema mismatch fails: `ContextCardsSchemaTests`, all recognized domains plus invented and blank claims. The board preserves the previous sample. This is a lab gate, not a system schema validation run.
- [x] Siri-disabled decision UI: `aSiriDisabledDeviceKeepsTheSameDecisionCard`, equal card values and Set Aside / Cancel labels. The host uses the false value. No Siri-disabled device or setting was tested.
- [x] Evidence identifies toolchain, hashes, adapter, and limits: the exported hosted attachment records seed/import SHA-256, source, and observed app-ui/app-intent receipts; execution is fixture.
- [x] Walkthrough never calls a fixture live integration: explicit fallback and system-presentation limits throughout.
- [x] Public-safe material only: original bundled seed and synthetic imported note; reviewed JSON only, no screenshots, recording, media, account, serial number, or store path.

**Cases.** New `ContextCardsQualificationHostTests` runs the session from a fresh seeded SQLite store: cancel, prepare/replace/refuse, confirm, reset beside a share-adopted original user record, and typed intent decline/retry/duplicate. Reset preserves imported item fields and its receipt. The duplicate returns the identical receipt and is listed once. New `ContextCardsQualificationTests` denies the underlying archive without a commit grant; the item and receipt store are unchanged. Existing checks cover invalid IDs, missing store/items, and stale content during confirmation.

**Changed:** two qualification test files, `evidence/LAB-002/`, the walkthrough, this ticket, experiment qualification notes, accessibility review flows (manual checks not-run), installed-SDK correction, and BUILD_STATUS rows. No app code, shared host hooks, target, entitlement, `project.yml`, or generated Xcode project changes. Catalog regenerated on research; output unchanged.

**Source correction:** the installed iOS 27.0 `_AppIntents_SwiftUI` interface puts `AppIntent.requestConfirmation(..., content:)` at macOS 15.0 / iOS 18.0 / watchOS 11.0 / tvOS 18.0. Earlier ledger wording conflated this with result-with-content's older availability. Spec and ledger corrected; deployment floor unchanged. S02, S03, and S64 primary pages consulted.

**Commands and results:** full `script/test.sh` passed through `labr` at embedded revision 317b4b1-dirty (the mirror’s generated local bundle-prefix configuration). Mac, iPhone, Watch, TV, and release profiles passed. The iPhone xcresult reports 9 passed, 0 failed/skipped, on iPhone 18 Pro / iOS 27.0 (24A434); the second JSON is explicitly host smoke, not an experiment interaction. The LAB-002-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md) record the actual narrow tests, hosted result bundle and exported attachment, SDK probe, catalog generation, validators, and full gate.

**Not run:** physical iPhone/iPad; experiment-specific iPhone simulator interaction; Siri or Shortcuts app; system snippet/confirmation/authentication; manual VoiceOver, Voice Control, Full Keyboard Access; large-text/contrast audit; iPad; 26-SDK compile. Simulator host smoke does not establish these gates.

**Known limits:** two Mac windows share one published context; last publisher wins and leaving a page clears it. No Context Cards curated App Shortcut. Context resolution is always unavailable. Source accessibility review found no dedicated menu commands for replacement or Set Aside…; system snippet children need an actual accessibility audit. Device and manual accessibility work remain for the owner; no promotion to `device-verified` or `release-ready`.

**Next dependency-ready ticket:** LAB-003-B (LAB-003-A and CORE-007/009/010 are done).
