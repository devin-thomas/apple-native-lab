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
