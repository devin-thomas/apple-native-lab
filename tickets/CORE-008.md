---
id: "CORE-008"
title: "Separate capability-heavy targets from the baseline"
status: "done"
milestone: "M0"
kind: "implementation"
depends_on: ["CORE-001", "CORE-004"]
---

# CORE-008 — Separate capability-heavy targets from the baseline

## Goal

Allow a new developer to build the core without qualifying every advanced entitlement.

## Authority and scope

Read the [governing specification](../SPEC.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** Workspace target graph, entitlements per target, configuration documentation.

## Implementation steps

1. Define CoreLocal, SystemSurfaces, Companions, CloudOptional, and FrontierOptional profiles
2. Keep extension entitlements attached only to the correct executable
3. Add ignored local signing/container overrides with safe documented examples
4. Test the core with every optional profile disabled

## Acceptance criteria

- [x] Missing PCC/CarPlay/File Provider setup cannot fail CoreLocal compilation. (CoreLocal targets attach only `Config/Profiles/CoreLocal.xcconfig`, embed nothing, and reference no optional identifier or entitlement. A clean copy with no `Config/Local.xcconfig`, no team, and no container built all three schemes.)
- [x] Identifiers are configurable without a maintainer-owned container. (App Group, Keychain group, and CloudKit container derive from `LAB_BUNDLE_PREFIX`; an override in a local file changed all three.)
- [x] No target links frameworks unsupported on its platform by accident. (`otool -L` per product; `Config/ProductPolicy.txt` allowlists frameworks per profile and platform and names the unsupported ones; the manifest fails anything else, shown with deliberate violations.)
- [x] The release manifest identifies which profiles were actually built. (`script/build_manifest.py` records built, failed, or skipped with the reason for each profile, and SDK, Xcode, and revision read from each product.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-29)

**Changed:** `project.yml`, `AppleNativeLab.xcodeproj` (regenerated), `Apps/Mac/Info.plist`, `Apps/Phone/Info.plist`, `Apps/Watch/Info.plist` (regenerated from `project.yml`), `Config/Base.xcconfig`, `Config/Local.xcconfig.example`, new `Config/Profiles/{CoreLocal,SystemSurfaces,Companions,CloudOptional,FrontierOptional}.xcconfig`, new `Config/PurposeStrings.xcconfig`, new `Config/ProductPolicy.txt`, new `script/build_manifest.py`, `script/test.sh`, `docs/BUILD_AND_DISTRIBUTION.md`, `docs/BUILD_STATUS.md` (schemes, known constraints, evidence rows). No Swift source, package, or CI file changed.

**What exists now:**

- Five build profiles, each a target-level xcconfig in `Config/Profiles/` that sets `LAB_BUILD_PROFILE` (which reaches the `LabBuildProfile` Info.plist key), a Swift compilation condition (`LAB_PROFILE_CORE_LOCAL` and so on), and its external setup. `LabMac`, `LabMacTests`, and `LabPhone` attach CoreLocal; `LabWatch` attaches Companions, which replaces its hard-coded Info.plist value. SystemSurfaces, CloudOptional, and FrontierOptional have no targets: a later target joins by attaching the file and getting its own scheme. No placeholder target was created.
- Entitlements stay per executable: the only one is the Mac App Sandbox on `LabMac`. `Config/ProductPolicy.txt` lists the frameworks and entitlements each profile may use per platform, and the platform traps recorded by CORE-004 (ARKit and NearbyInteraction on macOS, FoundationModels on watchOS and tvOS, Speech on tvOS).
- Identifiers derived from `LAB_BUNDLE_PREFIX` in `Config/Base.xcconfig`: `LAB_APP_GROUP_IDENTIFIER`, `LAB_KEYCHAIN_GROUP`, `LAB_CLOUDKIT_CONTAINER_IDENTIFIER`, with documented overrides in `Config/Local.xcconfig.example` and the paid-team requirement for on-device SystemSurfaces and CloudOptional proof.
- A distribution lane, `LAB_DISTRIBUTION_LANE`, recorded in each Info.plist as `LabDistributionLane`. Source (default) declares no purpose strings, so the probes and the Readiness screen behave exactly as before. Store merges honest purpose strings for exactly the privacy-sensitive frameworks each host links.
- `script/build_manifest.py` builds the selected profiles in Release and writes `build/manifest/manifest.json`. `script/test.sh` now ends with it.

**Evidence:** see the CORE-008 rows of the evidence log in [BUILD_STATUS](../docs/BUILD_STATUS.md). In summary: regeneration is stable; `script/test.sh` passed; a clean copy with no local configuration built `LabMac-Core`, `LabPhone-Core` (iOS simulator), and `LabWatch` (watchOS simulator); the manifest built CoreLocal and Companions and skipped the three profiles without targets, in both lanes; Source-lane Info.plists differ from the previous build only by the new lane key; the manifest failed each deliberately broken product in a throwaway copy, including a SystemSurfaces widget extension embedded in the iPhone host.

**Not run:** a Store archive, export, or upload (needs a paid team and publication approval); device-SDK builds in the manifest (it builds the Mac and the simulators); device builds of the optional profiles (no targets yet; SystemSurfaces and CloudOptional need a paid team on device); a Mac launch after this change (the Source-lane Info.plist gained only the lane key); a compile against a 26 SDK.

**Specification notes:**

- Store-lane Info.plist generation also applies Xcode's generated defaults: on the Mac `CFBundleName` becomes `NativeLab` instead of `Native Lab`, iOS adds `LSRequiresIPhoneOS`, and watchOS adds an unused `MinimumOSVersion~ipad`. Source builds are unaffected. Review before the first upload.
- An empty `INFOPLIST_KEY_` value is still written to the Info.plist as an empty string, with a warning. That is why the lane switches Info.plist generation rather than blanking the strings.
- Package targets do not receive xcconfig settings, so `LAB_SDK_27` and the profile conditions apply only to app and extension sources.
- A locally signed Mac build carries `com.apple.security.get-task-allow`, added by Xcode, besides the declared App Sandbox.

**Next dependency-ready tickets:** CORE-003 and CORE-007, whose dependencies are all done. CORE-008 unblocks nothing by itself: every LAB-nnn-A ticket that lists it also waits on CORE-003, CORE-005, and CORE-006.
