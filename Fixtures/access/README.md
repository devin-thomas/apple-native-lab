# Access as a Superpower fixtures

Original chart data for [LAB-035](../../experiments/LAB-035-access-as-a-superpower.md), built only from the lab's own demo seed ([`demo/seed.json`](../demo/seed.json)). Nothing here is external data, and it is distributed under the repository's MIT License ([ASSET_POLICY](../../docs/ASSET_POLICY.md)).

## `archive-chart.json`

The task is "Which demo collection has the most archived samples? Restore one sample from that collection." A first run archives nothing, so the experiment's Set Up Practice control archives six demo samples through the operation service, one receipt each. This file states those six samples and the exact reading of the chart they produce, so the chart's text and audio can be checked exactly.

| Key | What it holds |
|---|---|
| `practice` | The six sample IDs, in the order they are archived, with their titles and collections: 3 mineral specimens, 2 pigment swatches, 1 paper stock sample. The answer is the middle bar, not the first. |
| `chart` | The whole `ChartSemantics` value: title, summary, the categorical collection axis, the numeric archived-samples axis (0 to 4, a gridline at each sample), and one series with a labeled point per collection. The Audio Graph descriptor is built from this value. |
| `spoken` | How the value axis reads each value, and what VoiceOver reads for each bar: its label, its value, and its Restore actions in order. |
| `task` | The question, the answer, and two restores: one that finishes the task and one that does not, each with its result sentence and the summary afterwards. |

`AccessSuperpowerTests` in `Packages/LabFeatures` fails if the compiled practice set differs from `practice`, if a practice ID is not a demo sample in the stated collection, or if any reading differs from this file. The IDs are the demo seed's own; never change one here without changing the seed.
