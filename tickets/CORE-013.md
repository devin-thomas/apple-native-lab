---
id: "CORE-013"
title: "Bring up the Apple TV host and an all-platform smoke gate"
status: "in-progress"
milestone: "M1"
kind: "implementation"
depends_on: ["CORE-001", "CORE-004", "CORE-008"]
---

# CORE-013 — Bring up the Apple TV host and an all-platform smoke gate

## Goal

Add a native tvOS host beside the Mac, iPhone, and Watch hosts, and give every host a repeatable smoke check in the simulator and on paired devices, so later work can cover all four platforms at once instead of waiting for each experiment to introduce its platform.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). This ticket brings forward the Apple TV host that [SPEC](../SPEC.md) originally deferred to the TV experiments; it adds no TV experiment.

**Owned areas:** `Apps/TV`, the `LabTV` target and scheme and its Info.plist, `script/install_tv.sh`, the platform smoke steps in `script/test.sh`, host smoke test targets for tvOS and watchOS, tvOS lines in `Config/ProductPolicy.txt`, the public CI workflow's tvOS compile, and the Apple TV sections of `docs/DEVICE_SETUP.md` and `docs/BUILD_AND_DISTRIBUTION.md`.

## Implementation steps

1. Add a `LabTV` tvOS application target and scheme with a tvOS 26.0 floor, linking the shared support and catalog packages. It shows the catalog, an experiment's detail, and Readiness with focus navigation, large readable type, and a Menu-button escape path. Use the same bundle identifier as the iPhone host (`$(LAB_BUNDLE_PREFIX).nativelab`), so a signing team needs no new App ID. Choose its build profile from the profile table; the Watch host's Companions profile is the precedent.
2. Give the tvOS host the lab's app icon and a Top Shelf image, generated from the same source as the other platforms.
3. Add `script/install_tv.sh`, matching `install_watch.sh`: without arguments it lists usable tvOS destinations; with a device identifier it builds, installs, and launches.
4. Add host smoke tests that run inside the tvOS and watchOS hosts in a simulator (catalog present in the bundle, build provenance, readiness snapshot with no permission prompt), plus the shared package tests on the tvOS and watchOS simulators, which now have runtimes.
5. Extend `script/test.sh` so a device-free run builds all four hosts and runs the smoke tests on macOS, the iOS simulator, the watchOS simulator, and the tvOS simulator. Extend the release manifest and product policy to the tvOS host. Add the tvOS simulator compile to public CI within the workflow policy.
6. Document Apple TV pairing, Developer Mode, and installation in `docs/DEVICE_SETUP.md`.

## Acceptance criteria

- [ ] `LabTV` builds for the tvOS simulator and for a device from a clean checkout with the neutral `org.example` defaults and no local configuration.
- [ ] Focus moves through the catalog, a detail page, and Readiness with the remote alone, and the Menu button always leads back.
- [ ] The tvOS host links no framework that product policy marks unsupported on tvOS (FoundationModels, Speech) and declares no entitlement.
- [ ] `script/test.sh` runs the smoke tests on all four platforms without any device attached, and the release manifest records the tvOS host.
- [ ] `script/install_tv.sh` lists destinations, and installs and launches on a paired Apple TV in Developer Mode.
- [ ] Public CI compiles the tvOS host, and the workflow validator still passes.

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.
