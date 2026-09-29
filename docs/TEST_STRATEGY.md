# Test and evidence strategy

## Layers

Unit tests cover typed IDs, validation, authorization, idempotency, migrations, conflicts, package parsing, proposal-to-operation conversion, and state machines. Deterministic fixtures cover normal, empty, malformed, stale, duplicate, cancelled, and denied cases. Import fuzzing exercises archives and bounded text/media headers without creating unbounded workloads.

Adapter integration tests cover actual intent/entity resolution, extension staging, model readiness, permission-denial routing, storage snapshots, and peer protocol admission. AppIntentsTesting is a system-path tool with its own signing requirements, not a replacement for pure domain tests. [S05](SOURCE_INDEX.md#s05).

UI tests cover the M1 journey, reset boundaries, keyboard/VoiceOver affordances, unreadable small/large layouts, focus management, and error recovery. Accessibility audits support but do not replace hands-on assistive-technology review.

Device tests cover camera/AR/LiDAR, spatial audio/headphone behavior, microphone routes, real Watch transport, Apple TV Continuity Camera, UWB, haptics, background expiration, and managed capabilities. A simulator can validate views/state machines while leaving these tests `not-run`.

## Evidence states

Every test result is `passed`, `failed`, `blocked`, or `not-run`. Record the path as `physical`, `simulator`, `fixture`, or `static review`. A fixture pass does not upgrade a physical adapter. Tests should record both the preferred adapter and the usable unavailable path.

Use [EVIDENCE_TEMPLATE](EVIDENCE_TEMPLATE.md). Include exact toolchain/OS/device information without private serial numbers. Store evidence by experiment and source revision. Screenshots and recordings are selected artifacts subject to the privacy/rights policy; raw sessions are not uploaded automatically.

## M1 release gates

A clean checkout builds the declared CoreLocal schemes. The first-run flow works offline with original fixtures and no sign-in. The integrated share/import → review → commit → query → surface flow produces consistent records and receipts. The manual path is complete when intelligence is unavailable. Duplicate imports do not duplicate data. Reset Demo leaves a deliberately imported user record intact. A failed optional extension profile does not block the core build.

Essential navigation passes the accessibility matrix. A release archive passes link validation, dependency checks, source/asset license inventory, secret scans, and manual metadata inspection. Installation instructions are tested on the actual advertised distribution path.

## Proposed performance budgets

These are design targets to measure, not results. On the minimum tested Mac and iPhone, the catalog should become interactive within 2 seconds after a warm launch with bundled fixtures; common local edits should acknowledge UI input within 100 ms even when processing continues; an idle catalog should have no continuous polling/render loop. Use bounded memory and streaming for large media, with measured peak memory reported per task.

For real-time sessions, report median/p95 command admission delay, queue length, packet/retry observations, clock uncertainty, and reconnect time under a declared network. Do not claim hard real-time behavior or advertise a latency number without a reproducible test. For models, separate asset download, cold start, warm start, generation, validation, and correctness. A failed task cannot count as a performance improvement.

Thermal behavior, battery impact, and memory pressure should be observed over a declared run duration on actual hardware. Reduce quality or stop safely under pressure. No benchmark should hide failures through silent fallback.

## Evidence records

Structured evidence lives at `evidence/<ticket-or-experiment-ID>/<name>.json` and is validated by `script/validate/all.py` against the `EvidenceRecord` schema in `Packages/LabSupport`. A physical-device record is the only path to `device-verified`; a simulator or fixture record supports at most `implemented`, and a static review supports at most `spiked`.
