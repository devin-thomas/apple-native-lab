---
id: "CORE-001"
title: "Pin the toolchain and create independent core schemes"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: []
---

# CORE-001 — Pin the toolchain and create independent core schemes

## Goal

Establish an actual, reproducible Mac/iPhone workspace before API-specific implementation.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Workspace, safe Config defaults, script/build_and_run.sh, generated BUILD_STATUS documentation.

## Implementation steps

1. Inspect repository boundaries; initialize only this root if no Git repository exists
2. Record exact Xcode/Swift/SDK and compatible host macOS requirements
3. Create minimal native Mac and iPhone schemes with safe configurable bundle identifiers
4. Add a real Mac build-and-run entry point that opens the produced .app bundle

## Acceptance criteria

- [x] A clean checkout compiles the minimal core schemes without private configuration.
- [x] The selected deployment floor and advanced-adapter boundary are documented with actual compiler evidence. (27 SDK evidence recorded; a 26 SDK compile is an explicit not-run gate.)
- [x] A new developer can change team/bundle prefix without editing application source.
- [x] A missing optional capability is not linked into CoreLocal.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:** `project.yml`, `AppleNativeLab.xcodeproj`, `Config/Base.xcconfig`, `Config/Local.xcconfig.example`, `Apps/{Shared,Mac,Phone,Watch}`, `Packages/LabSupport`, `Packages/LabFeatures` (LabCatalog), `Tests/LabMacTests`, `script/*`, `docs/BUILD_STATUS.md`, `docs/DEVICE_SETUP.md`, `.gitignore`.

**Commands and results:** see the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). `script/test.sh` passed: catalog check, 12 package tests, 3 hosted Mac smoke tests, and iPhone and Watch simulator compiles. A clean copy without `Config/Local.xcconfig` built all three schemes. The Mac host was installed locally; the iPhone host was installed and launched on a physical iPhone 16 Pro (iOS 27.0).

**Optional capabilities:** the only entitlement is the Mac App Sandbox. No optional framework or capability is linked.

**Not run:** compile against a 26 SDK; physical Watch install (no destination available); iPad and Apple TV.

**Specification notes:** schemes use the proposed names. The Watch host is a Companions-profile smoke host that installs directly to the Watch, added early so paired-Watch installation can be qualified before LAB-021.

**Next dependency-ready tickets:** CORE-002 and CORE-004 (parallel), then CORE-003, CORE-007, and CORE-008.
