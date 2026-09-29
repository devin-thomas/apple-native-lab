# Evidence record template

Copy this into the implemented repository's evidence area for an actual run. This template records no successful test.

| Field | Value |
|---|---|
| Experiment / ticket | Record exact IDs |
| Source revision | Actual commit or explicitly uncommitted working tree |
| Run state | not-run / passed / failed / blocked |
| Execution path | physical / simulator / fixture / static review |
| Toolchain and SDK | Exact measured versions |
| OS and device class | No serial numbers or account identifiers |
| Capability / permission state | Record before and after, without secrets |
| Input fixture hash | Hash of the actual selected input |
| Steps | Reproducible sequence |
| Expected result | Observable behavior |
| Observed result | What actually happened |
| Measurements | Units, timing boundaries, sample count, failures |
| Artifacts | Approved relative paths, hashes, and rights classification |
| Limitations | Untested platforms, simulations, uncertain results |
| Cleanup | Resources/permissions/session data reset |

## Claim audit

For every sentence that says the experiment “supports,” “runs,” “recognizes,” “syncs,” or “works,” identify the result that supports it. A source document supports intended API use, not a tested product claim.

## Exported evidence

`EvidenceExporter` in `Packages/LabDemo` fills this template from actual runs. Its folder holds the selected artifacts, a `summary.md` whose first line is the worst result, and a `manifest.json` (`format: "native-lab-evidence-export"`, `formatVersion: 1`) with:

- the source revision and toolchain (`BuildProvenance`);
- each run's adapter, store, timebase, input hashes, and replay fingerprint;
- every artifact's path, SHA-256, size, rights tier, and review decision;
- every failure and unrun step, and the untested areas;
- performance claims, each linked to the exported run that measured it.

Only `public-fixture` artifacts are exported without an override. An override names the artifact, its tier, and a reason, and the manifest records it. `sensitive` artifacts are never exported. Source files are exported under names the person chooses, and their original paths are not recorded.
