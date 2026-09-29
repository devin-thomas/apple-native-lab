---
id: "CORE-007"
title: "Establish automated tests and evidence discipline"
status: "planned"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001", "CORE-002", "CORE-004"]
---

# CORE-007 — Establish automated tests and evidence discipline

## Goal

Make every future claim traceable to an actual test path.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Tests, future CI workflows, evidence utilities.

## Implementation steps

1. Create unit and adapter test targets with deterministic fixtures
2. Implement a structured evidence record and status vocabulary
3. Add Markdown links, ticket dependencies, and schema checks to CI
4. Keep public PR tests unsigned and without secrets or private runners

## Acceptance criteria

- [ ] CI can distinguish not-run/blocked from passed. (The workflow's own commands passed a local rehearsal, including the blocked path, but no GitHub Actions run has happened yet.)
- [x] A simulated result cannot be labeled physical-device proof. (Exhaustive promotion test over every path, result, and state; decoding refuses device fields off the physical path.)
- [x] A broken local documentation link or dependency cycle fails validation. (Negative fixtures in temporary copies: exit 1 with file, line, and cycle path.)
- [ ] Fork PR execution has no signing credentials or personal-data access. (Static review and the `workflow-policy` validator pass; no fork pull request has run yet.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:** [`Packages/LabSupport/Sources/LabSupport/Evidence/`](../Packages/LabSupport/Sources/LabSupport/Evidence/) (new: `RunResult.swift`, `Execution.swift`, `EvidenceRecord.swift`, `StatePromotion.swift`), `BuildProvenance.swift` (Codable and a memberwise initializer; existing API unchanged), three new test files in `Packages/LabSupport/Tests/LabSupportTests/`, [`script/validate/`](../script/validate/all.py) (new), [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) (new), and evidence rows in [BUILD_STATUS](../docs/BUILD_STATUS.md). No change to `project.yml`, `Config/`, the Xcode project, `Apps/`, other packages, or existing scripts.

**Evidence vocabulary and record:**

- `RunResult` is exactly `passed`, `failed`, `blocked`, or `not-run`. Only `passed` passes. `RunResult.combining` returns the worst result (failed, then blocked, then not-run), and an empty set is `not-run`. Decoding refuses any other word, such as `skipped` or `Passed`.
- `RunOutcome` pairs a result with non-empty text: what was observed, or why the check did not run. Its summary and `EvidenceRecord.logRow` always lead with the record's own result, so a blocked or not-run check never renders as passed.
- `Execution` is `physical(PhysicalDevice)`, `simulator(SimulatedDevice)`, `fixture`, or `staticReview`. Only the physical case carries a device (class, OS, and optional provisioning-profile expiry). `PhysicalDevice` refuses values that look like serial numbers, UDIDs, or UUIDs. Decoding refuses device fields on any other path. `Execution(observing:)` maps a simulator `DeviceSnapshot` to the simulator path.
- `EvidenceRecord` holds the ticket or experiment ID, check, date (whole seconds, ISO 8601 UTC), `BuildProvenance` (source revision, SDK, Xcode), execution, input IDs, steps, outcome, and limitations. Every initializer validates, including decoding. It is JSON schema version 1.
- A record does not choose the state it supports. `supportedState` follows from the path and result: a passing physical record supports at most `device-verified`, a simulator or fixture record `implemented`, and a static review `spiked`. Records that did not pass support nothing.
- `DeviceProof` can be created only from a passing physical record and is not `Decodable`. `ImplementationState.promoted(to:by:)` reaches `device-verified` only through it. No record reaches `release-ready`, which also needs review, and `specified` and `blocked` are not promotions.

**Evidence location:** one JSON `EvidenceRecord` per file at `evidence/<ticket-or-experiment-ID>/<name>.json`. None are stored yet. BUILD_STATUS remains the readable log, and `logRow` renders rows for it.

**Validators** (`python3 script/validate/all.py`, Python 3 standard library only; exit 0 passed, 1 failed, 3 blocked, 4 not-run):

| Check | What fails it |
|---|---|
| `links` | A local link or anchor that does not resolve, escapes the repository root (including through a symbolic link), differs in case from the file, or points at a file Git ignores. It reads inline links, images, reference definitions, and HTML `href`/`src` outside code, and it matches GitHub heading anchors, including `-1` suffixes for repeated headings |
| `ticket-frontmatter` | Missing or unknown keys, non-JSON values, an unknown status or kind, or an ID that does not match the file name |
| `ticket-graph` | A `depends_on` with no ticket file, or any cycle, reported as a path. It is `blocked` when unreadable frontmatter leaves the graph incomplete |
| `experiment-frontmatter` | A state outside the SPEC section 7 vocabulary, an unknown category or dependency, or an experiment cycle |
| `state-vocabulary` | SPEC.md, `ImplementationState`, and the catalog generator disagree. It is `blocked` if the SPEC sentence disappears |
| `catalog` | `script/generate_catalog.py --check` fails. It is `blocked` if the generator is missing |
| `evidence-records` | A stored record that would not decode, sits in the wrong folder, names an unknown subject, or carries extra keys such as a claimed state |
| `workflow-policy` | `pull_request_target` or `workflow_run`, a `secrets.` reference, any permission beyond read, a self-hosted runner, or an action not pinned to a commit SHA |

`python3 -m unittest discover -s script/validate/tests` runs 91 self-tests. Negative fixtures are written only into temporary copies of the repository.

**CI:** `.github/workflows/ci.yml` runs on `pull_request` and pushes to `main` on the GitHub-hosted `macos-26` runner, with `permissions: contents: read`, no secrets, no caches, and checkout pinned by SHA with credentials not persisted. It prints the runner's Xcode and SDKs, then selects Xcode 27 only if one is installed, otherwise the newest 26.x. It runs the validators and their self-tests, the three package test suites, the Mac hosted tests with an ad hoc signature, and unsigned iPhone and Watch simulator builds. It records each scheme's SDK and whether `LAB_SDK_27` was compiled in. When a 27 and a 26 Xcode are both installed, it also compiles the three schemes with the 26 SDK. Every step writes to a run ledger through `script/validate/ci.py`, and the last step publishes it as the job summary. A required check with no entry is `not-run`, a test step that ran zero tests is `not-run`, and the job passes only when every required check passed. Device qualification and signed builds are always listed as not run.

**Not run:**

- Any GitHub Actions execution, including a fork pull request. Nothing was pushed from this environment, so criteria 1 and 4 stay open until the first run.
- A compile against a 26 SDK. Only Xcode 27 is installed here, so the compatibility step recorded `not-run`. CI runs it when the runner has a 26.x Xcode.
- Any physical-device check. None is in scope.

**Specification notes:**

- Static review supports at most `spiked`. SPEC section 7 does not say what static review can establish, and this is the conservative reading.
- Ticket status accepts `planned`, `in-progress`, `blocked`, and `done`.
- `.gitignore` does not ignore `__pycache__/`. The validators avoid writing bytecode, so no entry is needed for them.
