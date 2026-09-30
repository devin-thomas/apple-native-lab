# Build and distribution contract

## Toolchain baseline

Plan against the Xcode 27 SDK family, with a 26-family deployment floor for the core iOS/iPadOS/macOS/watchOS/tvOS hosts where practical. Gate 27-generation features in isolated adapters with compile-time and runtime availability checks. This is an explicit product choice, not a claim that every linked API exists on OS 26. Xcode's own compatible macOS requirement is a separate gate. [S08](SOURCE_INDEX.md#s08).

The installed Xcode build, Swift compiler, SDK versions, deployment floor, and every successful compile are recorded in [BUILD_STATUS](BUILD_STATUS.md), from real runs only. Do not guess a patch version, device identifier, SDK symbol, or simulator destination. If the verified SDK changes this plan, record the new requirement before proceeding.

## Build profiles

| Profile | Intended contents | Configuration | Schemes today | External setup |
|---|---|---|---|---|
| CoreLocal | Mac/iPhone host, original fixtures, local persistence, manual/fallback experiments, eligible local inference | `Config/Profiles/CoreLocal.xcconfig` | `LabMac-Core`, `LabPhone-Core` | None for the Mac and simulators; any team, including a free Personal Team, for a device |
| SystemSurfaces | Share/widget/Control extensions, App Group staging, App Intents metadata and integration tests | `Config/Profiles/SystemSurfaces.xcconfig` | `LabPhone-Surfaces` | Own paid team for on-device App Group staging; simulator builds need none |
| Companions | Separate Watch and TV hosts plus LAN/Watch relay | `Config/Profiles/Companions.xcconfig` | `LabWatch` | Physical devices for real transport/camera evidence |
| CloudOptional | CloudKit, optional PCC/provider adapters | `Config/Profiles/CloudOptional.xcconfig` | none yet | Own paid team with iCloud, own container, explicit account/entitlement/route configuration |
| FrontierOptional | File Provider, App Clip, Wallet signer integration, CarPlay/PTT/Screen Time/accessory spikes | `Config/Profiles/FrontierOptional.xcconfig` | none yet | Per-feature setup and managed approval where required |

A CoreLocal build must not fail because a FrontierOptional target lacks approval. An unavailable live adapter must have an explanation and its declared fallback. Personal development, App Store distribution, Developer ID, managed capabilities, and test distribution are not interchangeable. [S37](SOURCE_INDEX.md#s37).

### How a profile is wired

Build settings are layered. A later layer overrides an earlier one:

```text
Config/Base.xcconfig                 project level: bundle prefix, team, provenance, lane, shared identifiers, SDK flags
  Config/PurposeStrings.xcconfig     Store-lane purpose strings (included by Base)
  Config/Local.xcconfig              ignored local overrides (included last, optional)
Config/Profiles/<Profile>.xcconfig   target level: LAB_BUILD_PROFILE and the profile's compilation condition
project.yml target settings          per executable: bundle ID, entitlements file, purpose-string keys
xcodebuild arguments from script/    LAB_SOURCE_REVISION, and LAB_DISTRIBUTION_LANE for the manifest
```

1. **Every target attaches exactly one profile file** through `configFiles` in `project.yml`. Its `LAB_BUILD_PROFILE` becomes the `LabBuildProfile` Info.plist key, which the Readiness screen shows and the release manifest checks. The profile file sits above `Config/Local.xcconfig`, so a local override cannot relabel a target.
2. **A profile without targets is still real configuration.** Its file names the profile, its external setup, and a Swift compilation condition (`LAB_PROFILE_CORE_LOCAL`, `LAB_PROFILE_SYSTEM_SURFACES`, `LAB_PROFILE_COMPANIONS`, `LAB_PROFILE_CLOUD_OPTIONAL`, `LAB_PROFILE_FRONTIER_OPTIONAL`). The release manifest lists it as skipped, with the reason. A new target joins a profile by attaching that file and getting its own scheme. Do not create empty placeholder targets.
3. **CoreLocal depends on nothing optional.** No CoreLocal target embeds or depends on a target from another profile, references the App Group, Keychain group, or CloudKit identifiers, or declares an entitlement other than the Mac App Sandbox. SystemSurfaces extensions are embedded by a separate SystemSurfaces host variant with its own scheme (for example `LabPhone-Surfaces`), so `LabPhone-Core` never needs App Group provisioning or extra App IDs. The Watch host installs directly to the Watch rather than being embedded in the iPhone app.
4. **Entitlements stay with their executable.** Each executable or extension target declares its own `.entitlements` file in `project.yml`. Today the only one is `Apps/Mac/LabMac.entitlements`, which holds the App Sandbox. [`Config/ProductPolicy.txt`](../Config/ProductPolicy.txt) lists the entitlements and frameworks each profile may use on each platform; the release manifest fails a product that goes beyond it.
5. **Packages do not see these settings.** `Packages/*` build with their own settings, so neither the profile conditions nor `LAB_SDK_27` reach package code. Code that differs by profile lives in the app or extension sources, or behind a protocol the host injects.

## Project and run entry points

The committed `AppleNativeLab.xcodeproj` is generated from `project.yml` by `script/generate_project.sh` (XcodeGen), so a clean checkout builds without XcodeGen. Sources are synchronized folders; regenerate only when targets, settings, packages, or schemes change, and review the diff. Current schemes are listed in [BUILD_STATUS](BUILD_STATUS.md). Proposed names for later hosts are `LabPhone-Surfaces` and `LabTV`.

| Script | Purpose |
|---|---|
| `script/build_and_run.sh` | Builds `LabMac-Core`, stops only the known lab process (`NativeLab`), and opens the real `.app` bundle |
| `script/test.sh` | Every automated check that needs no device, signing team, or network, ending with a Source-lane release manifest |
| `script/install_mac.sh`, `install_phone.sh`, `install_watch.sh` | Install routes. The device scripts list destinations first and take a device ID as data |
| `script/build_manifest.py` | Builds the selected profiles and writes the release manifest ([below](#release-manifest)) |
| `script/toolchain_report.sh` | Prints the installed toolchain for BUILD_STATUS |

Optional verification, log, or debug flags must not bypass signing or authorization. Treat untrusted command-line input as data and avoid shell interpolation.

## Signing and configuration

Tracked files hold neutral defaults, and `Config/Local.xcconfig` (ignored; start from `Config/Local.xcconfig.example`) holds the development team, bundle prefix, and any identifier override. Never commit a signing identity, provisioning profile, certificate private key, service token, real pass-signing key, or personal container export. Bundle IDs, App Groups, Keychain access groups, and CloudKit containers are configurable for every independent developer:

| Setting | Tracked default | Used by |
|---|---|---|
| `LAB_BUNDLE_PREFIX` | `org.example` | Every bundle identifier |
| `DEVELOPMENT_TEAM` | empty | iPhone, iPad, and Watch device builds |
| `LAB_MAC_DEVELOPMENT_TEAM` | empty, so the Mac host signs to run locally | The Mac host |
| `LAB_APP_GROUP_IDENTIFIER` | `group.$(LAB_BUNDLE_PREFIX).nativelab` | SystemSurfaces App Group entitlement |
| `LAB_KEYCHAIN_GROUP` | `$(LAB_BUNDLE_PREFIX).nativelab.shared` | `keychain-access-groups`, written as `$(AppIdentifierPrefix)$(LAB_KEYCHAIN_GROUP)` |
| `LAB_CLOUDKIT_CONTAINER_IDENTIFIER` | `iCloud.$(LAB_BUNDLE_PREFIX).nativelab` | CloudOptional container entitlement |
| `LAB_DISTRIBUTION_LANE` | `Source` | Whether hosts declare purpose strings ([below](#purpose-strings-and-the-store-lane)) |

The shared identifiers derive from `LAB_BUNDLE_PREFIX`, so setting your own prefix gives you your own App Group and container, and no maintainer-owned container is assumed. Set one directly only to reuse an identifier you already registered. A target that needs an identifier at run time declares an Info.plist key with the setting as its value (for example `LabAppGroupIdentifier: $(LAB_APP_GROUP_IDENTIFIER)`), so Swift code never hard-codes one. Before the first Mac target uses an App Group, confirm the identifier form macOS expects against the installed SDK.

A free Personal Team builds and installs CoreLocal, but its profiles expire after seven days, it allows few developer apps per device and few new App IDs per week, and it cannot use App Groups, iCloud/CloudKit, or Push. On-device proof of SystemSurfaces App Group staging and of CloudOptional therefore needs a paid team; under a Personal Team those paths are recorded as `blocked`, not `failed`, and their fallbacks carry the experiment. CoreLocal never needs a paid team, and simulator builds of every profile need no team at all.

Start CoreLocal with only necessary capabilities. Add entitlement keys only after verifying official documentation and the actual target's provisioning profile. An identifier string is not approval. For a failing Mac artifact, inspect `codesign -dvvv --entitlements :-` and `spctl -a -vv` before classifying the failure as compile, signing, sandbox, or distribution trust. A locally signed build also shows `com.apple.security.get-task-allow`, which Xcode adds for development signing; an exported distribution build does not carry it.

## Distribution lanes

Source distribution is the first public lane. A user builds with their own local configuration. Mac binary distribution may later use Developer ID signing/notarization or an appropriate store lane. iPhone/Watch/TV distribution requires an Apple-supported installation path; do not promise a universally installable unsigned IPA. A simulator build is not a public device installer.

An optional App Store/TestFlight distribution can make advanced features convenient for users, but it is not a condition of reading or building the CoreLocal examples. Foundation Models PCC eligibility is particularly constrained and cannot be assumed for every developer or every source-built install. [S07](SOURCE_INDEX.md#s07).

### Purpose strings and the Store lane

The hosts link AVFoundation, CoreBluetooth, FoundationModels, and Speech (the iPhone also ARKit and NearbyInteraction; the Watch AVFAudio, CoreBluetooth, and NearbyInteraction) only to read capability status for the Readiness screen, without prompting. App Store processing can flag a binary that references these privacy-sensitive APIs without the matching purpose strings.

**Decision (CORE-008):** the distribution lane decides, per build, whether hosts declare purpose strings.

- **Source** (default): no purpose strings. The probes work unchanged, Readiness reports that this build cannot ask, and the permission stager falls back before asking. This is what every developer builds.
- **Store** (`LAB_DISTRIBUTION_LANE = Store`, set in `Config/Local.xcconfig` or passed to `xcodebuild`): each host declares honest purpose strings from `Config/PurposeStrings.xcconfig` for exactly the privacy-sensitive frameworks it links. The stager still asks only when an experiment action needs the permission.

The probes are not compiled out of store builds. That would need a LabSupport source change and a switch that package code cannot receive from an xcconfig file, and store builds would lose the Readiness screen.

How it works: each host sets `GENERATE_INFOPLIST_FILE = $(LAB_DECLARES_PURPOSE_STRINGS)` with `INFOPLIST_KEY_NS…UsageDescription` settings. The lane resolves that to `NO` for Source, so the Info.plist is exactly the tracked file, and to `YES` for Store, so Xcode merges the purpose strings into it. Store-lane generation also applies Xcode's generated defaults, observed with Xcode 27.0: on the Mac `CFBundleName` becomes the product name `NativeLab` instead of `Native Lab`; iOS adds `LSRequiresIPhoneOS`; watchOS adds an unused `MinimumOSVersion~ipad`. Review them before the first upload.

`script/build_manifest.py --lane Store` fails any product that links a framework named in a `purpose` line of `Config/ProductPolicy.txt` without the matching Info.plist key, so a Source build is caught before it reaches App Store processing.

Before any Store upload: reread every string against the experiments that build contains, review whether a privacy manifest is required, sign with a paid team, and get explicit approval for publication. When an experiment needs a permission in source builds too, move that host's purpose string into its Info.plist properties in `project.yml` and delete the matching `INFOPLIST_KEY_` line, so both lanes declare it.

## Release manifest

```sh
script/build_manifest.py                           # every profile, Source lane
script/build_manifest.py --profile CoreLocal       # only CoreLocal; the rest are recorded as skipped
script/build_manifest.py --lane Store              # Store lane: purpose strings required
```

The script reads the profiles from `Config/Profiles/`, assigns each scheme to the profile its application targets attach, and builds every scheme of each selected profile in Release from a fresh `build/manifest/DerivedData`: the Mac for `platform=macOS`, iOS and watchOS for their generic simulators. It writes `build/manifest/manifest.json` (ignored by Git) and one log per scheme, and exits non-zero if any selected profile failed.

The manifest records the source revision (and whether the tree was dirty), the Xcode, Swift, and host versions, the lane, and whether a local configuration was present. For each profile it records `built`, `failed`, or `skipped` with the reason. For each built scheme it records the exact `xcodebuild` command and, from the product itself, the SDK, Xcode build, minimum OS, profile, lane, revision, architectures, executable hash, linked frameworks and libraries, declared and signed entitlement keys, signature kind, purpose strings, and embedded bundles. A profile is `built` only if every one of its schemes built and every product passed these checks:

- the product was produced by this run and its Info.plist carries the expected profile, lane, and revision;
- every linked system framework is allowed for that profile and platform in `Config/ProductPolicy.txt`, none is marked unsupported on that platform, and no private framework is linked;
- every declared entitlement is allowed for the profile, and the signature adds nothing beyond the declared keys and Xcode's local-signing keys (`get-task-allow`, `application-identifier`, `team-identifier`);
- every app or extension embedded in the product declares the host's profile and passes the same framework and entitlement checks, and no scheme builds a target from another profile;
- in the Store lane, every purpose string required by a linked framework is present.

To link a new framework or declare a new entitlement, add a line with its reason to `Config/ProductPolicy.txt` in the same change. The manifest never records entitlement values, team identifiers, or a local bundle prefix, and it is not a release by itself: simulator products are not device installers, and the Mac product is signed for local use, not notarized.

## Release checklist

Release from an allowlisted checkout/artifact directory, never from its parent workspace. Include only approved source, docs, original assets, license notices, and actual tested outputs. Exclude local overrides, generated model downloads, databases, device traces, signing material, and adjacent projects. Rebuild from a clean checkout, write and inspect the release manifest, verify provenance and hashes, inspect the final archive contents, and test the documented install path on a fresh environment before calling a release ready.

## App Intents live in CoreLocal

App Intents need no entitlement, so Action Atlas's intents ship in the CoreLocal hosts (`Packages/LabFeatures` target `ActionAtlas`, registered through an `AppIntentsPackage`). SystemSurfaces keeps the extension targets (share, widget, Control, Live Activity) and the App Group they need.
