---
id: "LAB-007-B"
title: "Qualify and document Share Ingress Station"
status: "done"
milestone: "M1"
kind: "qualification"
depends_on: ["LAB-007-A", "CORE-007", "CORE-009", "CORE-010"]
---

# LAB-007-B — Qualify and document Share Ingress Station

## Goal

Prove Share Ingress Station on its declared live path and make unsupported-device behavior equally clear.

## Authority and scope

Read the [governing specification](../experiments/LAB-007-share-ingress-station.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** share-ingress-station tests, evidence, capability descriptor, experiment walkthrough.

## Implementation steps

1. Replay the complete fixture interaction from a clean state
2. Test these experiment-specific behaviors: Cloud-backed attachments can be cancelled safely; Multiple attachments preserve order and provenance; Malformed and oversized payloads never block future imports
3. Test denial, cancellation, stale/duplicate state, and reset without touching imported user data
4. Record physical-device evidence only for the actual tested adapter; preserve not-run states elsewhere
5. Review accessibility, rights, privacy, and the source/availability notes; add a publication-safe walkthrough

## Acceptance criteria

- [ ] Cloud-backed attachments can be cancelled safely.
- [ ] Multiple attachments preserve order and provenance.
- [ ] Malformed and oversized payloads never block future imports.
- [ ] Evidence identifies real toolchain, input hash, adapter, and limitations.
- [ ] The walkthrough never claims a simulation is the live integration.
- [ ] Only approved original/public-safe material enters screenshots and exports.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Qualification surface:** iPhone, iPad; separate Mac Share extension.

**Unavailable path:** Host-app file picker and paste action; extension not required for core build.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

**State: LAB-007 stays `implemented`.** Sharing from another app has run only in the simulator. The paste and file-picker fallback ran on the Mac (including a physical, agent-driven run of Choose Files) and in the simulator. The physical Mac record supports `device-verified` only for the Mac host's file-picker fallback, not for the declared iPhone and iPad share-extension surface.

**The run that would promote it.** With a team that can sign App Groups, install `LabPhone-Surfaces` on the iPhone, share the showcase `harbor-sketch.png` from Photos and a Safari page to Native Lab, add the link to one of your own collections, and confirm in a read-only store copy a committed receipt whose adapter is `share-extension`. Record it with `DeviceRunEvidence`.

**Choose Files on the Mac** needed no entitlement change: the runtime gate already accepts `com.apple.security.files.user-selected.read-write`, which LAB-008-A added. The disabled-with-reason path stays for any sandboxed build without either user-selected entitlement, covered by hosted tests.

**Acceptance.**

- [x] Cloud-backed attachments can be cancelled safely (fixture path): a chosen file whose coordinated read is held by a writer is cancelled in under 2 s and keeps nothing; a failed download is refused alone; an intake cancelled before it starts reads nothing; a retry after a cancel stages with its own origin; in the host, Cancel with a held download keeps nothing and the next paste works. No real iCloud download was cancelled.
- [x] Multiple attachments preserve order and provenance: 32 attachments and several extension items in the fixture tests, surviving a relaunch; the Mac's "2 of 3" and "3 of 3"; the simulator's Photos share "1 of 2" and "2 of 2". Known issue: two intakes in the same second can list out of order.
- [x] Malformed and oversized payloads never block future imports: every hostile fixture, text 1 byte over 2 MiB, a sparse file 1 byte over 1 GiB (refused without being copied), a forged staging record and a damaged import set aside; the next import is added with a receipt each time.
- [x] Evidence identifies real toolchain, input hash, adapter, and limitations: four records at 074eaaa (showcase replay and host intake-to-receipt on the fixture path, Mac Choose Files on the physical path, iPhone in the simulator).
- [x] The walkthrough never claims a simulation is the live integration: it opens with what is real and what is simulated and labels every screenshot as the simulator.
- [x] Only approved original material enters screenshots and exports: the showcase's 7 artifacts are `public-fixture`; the physical Mac record was reviewed before publishing and holds fixture names, hashes, and the device class only.

**Cases:** denial (grants for another collection or adapter, an expired grant, the model tool, demo and archived destinations), cancellation (intake and Add), stale state (removed in another window, changed after review), duplicates (two concurrent Adds of one import store one item), and Reset Demo leaving added and waiting imports alone.

**Changed:** `ShareInboxModel.swift` (a defaulted `canChooseFiles:` parameter so tests can render the disabled path), `Fixtures/showcase/share-ingress/` with four original intake files, qualification, replay, showcase, host evidence, and accessibility tests, `evidence/LAB-007/` (4 records), `docs/walkthroughs/LAB-007-share-ingress-station.md` with 4 simulator screenshots, share-ingress rows in the accessibility review and the SDK ledger, and the experiment spec's Choose Files correction and ⌘6 shortcut (its state is unchanged).

**Commands and results:** see the LAB-007-B rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). `script/test.sh` and `python3 script/validate/all.py` passed at 8c33adc.

**Platforms:** Mac passed (fixture, and physical for the file-picker fallback only). iPhone: simulator passed; physical not run, and the share extension on a device is blocked by App Groups. Watch and TV not applicable.

**Not run:** the share extension and App Group staging on a device (blocked), paste and Choose Files on a physical iPhone, a real iCloud cancel, Mac drag and drop, VoiceOver, Voice Control, and Full Keyboard Access, iPad, and a 26-family SDK compile.

**Follow-ups:** a pasted-then-shared duplicate is refused with advice to share again, which cannot help; same-second intakes need an arrival sequence before the batch ID; "n of N shared together" also appears on file-picker imports; Choose Files, Add, and Remove have no Mac menu commands, and Add is not pinned on iPhone; a committed UI-test target for `LabPhone-Surfaces` and `LabPhone-Core`.

**Next dependency-ready tickets:** CORE-012 (the M1 journey) once LAB-004-B lands; LAB-012-A.
