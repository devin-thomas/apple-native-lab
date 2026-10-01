# LAB-009 qualification evidence

LAB-009-B qualifies the available browser session and fixture model. The live-provider gate
remains blocked. Hosted replays do not drive Finder, Files, or an assistive technology.

Each JSON file is an EvidenceRecord with a measured toolchain or explicit static-review scope,
actual fixture hashes, adapter descriptions, and limitations. Raw result bundles remain in the
ignored build directory; only selected JSON attachments are stored here.

## Artifact review (2026-10-01)

All records below are approved original/public-safe material: fictional bundled sample hashes,
operation observations, and non-identifying toolchain metadata. No user document, account,
screenshot, recording, store, hardware identifier, or private path is included.

| Artifact | SHA-256 | Rights classification |
|---|---|---|
| [documents-everywhere-fixture.json](documents-everywhere-fixture.json) | `5cad303d91f9f0b7617bdacf24eaea2655e4c028895868d7336917c8de8d5dfc` | public-fixture (original samples and test observations) |
| [documents-everywhere-live-gates.json](documents-everywhere-live-gates.json) | `5fbe4d46260ad3cf0b8bbddd357a157a89a8692c50bd2d7927d05fce403ff7fb` | public-fixture (original samples and test observations) |
| [documents-everywhere-mac-host.json](documents-everywhere-mac-host.json) | `2c79482d1516d22264d801a0959923396ce0517a018a74f5d8bcb82a1c795936` | public-fixture (original samples and test observations) |
| [documents-everywhere-iphone-simulator-host.json](documents-everywhere-iphone-simulator-host.json) | `f48f61824223592389e3a5b05e6e4841cfdfa1713d1c9d3b6b1bffad1d50136f` | public-fixture (original samples and test observations) |

See the [ticket record](../../tickets/LAB-009-B.md),
[walkthrough](../../docs/walkthroughs/LAB-009-documents-everywhere.md), and
[build ledger](../../docs/BUILD_STATUS.md) for commands, outcomes, and unrun gates.
