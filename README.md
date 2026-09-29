# Apple Native Capability Lab

**Build unusually capable native Apple experiences—and make the mechanism inspectable.**

This is a public, local-first laboratory of 48 focused experiments spanning system actions, sharing, intelligence, audio, accessibility, continuity, spatial computing, media, and commercial integrations. Each experiment has a concrete user payoff, a bounded implementation, a fallback, and a device-evidence gate.

**Current state: foundation build (CORE-001).** Native Mac, iPhone/iPad, and Watch hosts build from this repository and browse the 48-experiment catalog, and a Readiness screen reports the real toolchain and device. Every experiment is still `specified`; nothing in the catalog claims to run yet. [BUILD_STATUS](docs/BUILD_STATUS.md) records what was actually built, tested, and installed, and what was not.

## Build and run

Requires Xcode 27 (the core targets the 26 OS family; see [BUILD_STATUS](docs/BUILD_STATUS.md)). No account, key, or private configuration is needed for the Mac or simulators.

```sh
script/build_and_run.sh      # build and open the Mac app
script/test.sh               # every automated check that needs no device
```

Device installs (iPhone, iPad, Apple Watch) use your own signing team: see [DEVICE_SETUP](docs/DEVICE_SETUP.md).

## Begin

Read [START_HERE.md](START_HERE.md), then [SPEC.md](SPEC.md). Builders follow [AGENTS.md](AGENTS.md) and [TICKETS.md](TICKETS.md). Explore the [48-experiment catalog](experiments/INDEX.md), [capability matrix](docs/CAPABILITY_MATRIX.md), and [showcase routes](showcases/INDEX.md).

The first release is six deeply integrated experiments—not 48 shallow screens. It demonstrates **share → inspect → commit → find → act → reflect state in a native surface**, with a useful manual path when a model or system integration is unavailable.

## Product promises

The core experience will run with synthetic, original fixtures and no account, API key, cloud subscription, private dependency, or new accessory. Advanced integrations are opt-in and isolated. An unavailable capability is explained, never faked. An experiment may be device-specific without pretending every Apple platform supports the same API.

The interface is native SwiftUI with narrow UIKit/AppKit interoperability. Mac means windows, menus, keyboard, and pointer; Watch means brief interactions; TV means a readable shared stage. Shared logic does not require identical screens.

## Repository map

| Area | Purpose |
|---|---|
| [SPEC.md](SPEC.md) | Scope, requirements, first release, and completion rules |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Packages, host targets, extension boundaries, and operation flow |
| [docs/DATA_CONTRACTS.md](docs/DATA_CONTRACTS.md) | Stable IDs, import formats, operation receipts, and network envelopes |
| [docs/BUILD_AND_DISTRIBUTION.md](docs/BUILD_AND_DISTRIBUTION.md) | Planned build profiles, signing, device qualification, and release paths |
| [docs/BUILD_STATUS.md](docs/BUILD_STATUS.md) | Recorded toolchain, schemes, evidence, and gates not yet run |
| [docs/DEVICE_SETUP.md](docs/DEVICE_SETUP.md) | Signing, Mac, iPhone, and Apple Watch installation |
| [docs/SECURITY_AND_PRIVACY.md](docs/SECURITY_AND_PRIVACY.md) | Consent, data minimization, hostile input, local networking, and release safety |
| [docs/TEST_STRATEGY.md](docs/TEST_STRATEGY.md) | Reproducible tests, evidence states, and hardware limits |
| [docs/SOURCE_INDEX.md](docs/SOURCE_INDEX.md) | Dated primary-source research and reference-only leads |
| [ADR.md](ADR.md) | Architecture decisions and their consequences |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to add a genuinely useful experiment |

MIT-licensed project material; independently supplied media, models, and dependencies retain their own licenses. See [LICENSE.md](LICENSE.md) and [docs/ASSET_POLICY.md](docs/ASSET_POLICY.md). Apple platform names are descriptive; this is not an Apple-sponsored or endorsed project.
