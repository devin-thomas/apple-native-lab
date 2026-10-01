# Local Model Bench

This build runs a deterministic fixture executor, not inference. No Core ML, Foundation Models, or MLX model is loaded by this experiment. Its nanoseconds are scripted inputs, its allocated model bytes are zero, and its cold/warm labels are supplied classes, not sensor readings. The qualification is package and Mac hosted fixture evidence. The retained user sample is an original item created through the operation service as a stand-in for imported data; no file-import adapter is qualified here. No experiment screen was driven on a physical mobile device or in a simulator.

On Mac, open **View › Local Model Bench** (⌥⌘3), or its sidebar row. On iPhone, open its catalog page and choose **Open Local Model Bench**. The phone route is compiled; this qualification did not drive it.

1. Choose **Download**, then **Warm-up**. Each produces its own report. Neither is a measured score; Download does not fetch an asset.
2. Choose **Measured, cold**. Four original tasks pass and the cold score reads `31000000 ns, fixture script`.
3. Choose **Measured, warm**. Its separate score reads `9000000 ns, fixture script`. These numbers cannot compare machines or predict real model performance. Combining cold and warm throws `mixedThermal`. The score uses the lower median: with four sorted samples, it takes the second value rather than averaging the middle pair.
4. The most recently completed run is selected. On Mac its JSON appears in the detail column and can be selected and copied. To select cold again, run cold again. There is no report picker, save-file dialog, or iPhone export surface.
5. Choose **Record Selected Run**. It records one item in **Bench results** through the authorization-checked app-UI operation and returns a receipt. Repeating the same report adds no item or receipt.
6. Choose **Reset Bench Results**, then confirm. It archives this experiment's marked report items, with archive receipts; other user items and demo items stay. The displayed in-memory reports remain. Recording the exact same report after reset returns the original receipt and leaves that item archived. Reset is not a way to produce a new benchmark result.

For refusal demonstrations, run the tests rather than loading a real model. `ModelGateTests` submits a 4,000,000,000-byte descriptor against 1,000 bytes and observes zero loader calls. An unreviewed license is also refused. `BenchScoreTests` inserts a wrong answer at 1 ns and observes `failedTask`, with no score. `FixtureExecutorTests` cancels before allocation and observes zero loader calls. These are injected boundary tests, not memory-pressure or operating-system permission tests.

`BenchQualificationTests` changes a report between reset's read and commit. Reset returns a conflict receipt and the changed item survives; a fresh reset can archive it. The current reset session reports the number of returned receipts, including conflicts, so consult the receipt inspector to distinguish a conflict from an archive. A missing reset grant leaves the report unchanged; a model tool cannot record.

The corpus `lab-015-fixture-v1` contains four original prompts and expected answers: repeat SLATE, count the letters in kestrel, add 19 and 23, reverse MAPLE. The SHA-256 of the canonical case list is in each report and the [evidence records](../../evidence/LAB-015/). No account, downloaded model, personal text, recording, or remote service participates. The published JSON was reviewed as original fixture material; no screenshots or media are included.

The source and availability boundary is recorded in the [SDK ledger](../VERIFICATION_BOUNDARIES.md#core-ml-lab-015) and [Core ML source note](../SOURCE_INDEX.md#s63). Apple's [model load](https://developer.apple.com/documentation/coreml/mlmodel/load(contentsof:configuration:)) and [compute plan](https://developer.apple.com/documentation/coreml/mlcomputeplan) are references for a future adapter, not integrations demonstrated here. The caller-declared memory check does not measure a model's real peak memory. The session uses total physical memory as its supplied budget, not currently free memory.

Accessibility review is [recorded separately](../ACCESSIBILITY_REVIEW.md#local-model-bench-lab-015-b). Standard buttons have visible names; no result depends on color or motion. VoiceOver, Voice Control, Full Keyboard Access, largest text, focus movement, and rendered contrast checks remain not-run. Run and record actions have no dedicated Mac menu commands, and result text is not explicitly announced by this session.

LAB-015 remains `implemented`. A future live adapter needs a reviewed original or public-safe model asset, an isolated runtime dependency, a defensible memory admission strategy, and real correctness/latency/memory/thermal evidence. Optional iPhone/iPad runs need the owner. This qualification promotes no hardware or inference claim.

Evidence review (2026-10-01):

| Artifact | Origin | Rights / decision | Claim |
|---|---|---|---|
| `local-model-bench-package-fixture.json` | Actual package test output, transcribed after 22 passing tests | Original test fixtures; `public-fixture`, approved | Scoring, gate, cancellation, denial, stale/duplicate contract |
| `local-model-bench-host-fixture.json` | Attachment exported from the passing Mac hosted replay (3 tests total) | Original corpus and synthetic user-data stand-in; `public-fixture`, approved | Session and LibraryBenchBackend on fresh SQLite state |

The host attachment's corpus digest matches the package record. Neither artifact contains raw test logs, machine identifiers, private paths, accounts, or media. The host report's OS is 27.0.0, executor is `fixture`, and inference is false. Attachments support at most `implemented`; the Mac is a real host but the executor path remains `fixture`.

The qualification's full `script/test.sh` passed repository checks and packages, then stopped at an unrelated Mac rendering test whose receipt list lacked `Finish Job`. Simulator host checks and the release manifest were not reached in this run. See the [ticket completion record](../../tickets/LAB-015-B.md) for the exact boundary; no all-platform pass is claimed.
