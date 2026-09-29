# Build and distribution contract

## Planning baseline, not a successful build claim

Plan against the Xcode 27 SDK family, with a 26-family deployment floor for the core iOS/iPadOS/macOS/watchOS/tvOS hosts where practical. Gate 27-generation features in isolated adapters with compile-time and runtime availability checks. This is an explicit product choice, not a claim that every linked API exists on OS 26. Xcode's own compatible macOS requirement is a separate gate. [S08](SOURCE_INDEX.md#s08).

CORE-001 must replace the family-level description with the exact installed Xcode build, Swift compiler, SDK versions, supported deployment targets, and a successful minimal compile for each selected scheme. Do not guess a patch version, device identifier, SDK symbol, or simulator destination. If the verified SDK changes this plan, record the new requirement before proceeding.

No application, scripts, project files, code-signing assets, or native build results are present in this Markdown-only pack.

## Build profiles

| Profile | Intended contents | External setup |
|---|---|---|
| CoreLocal | Mac/iPhone host, original fixtures, local persistence, manual/fallback experiments, eligible local inference | Local Xcode; own device signing where needed |
| SystemSurfaces | Share/widget/Control extensions, App Group staging, App Intents metadata and integration tests | Own compatible signing team and capabilities |
| Companions | Separate Watch and TV hosts plus LAN/Watch relay | Physical devices for real transport/camera evidence |
| CloudOptional | CloudKit, optional PCC/provider adapters | Explicit account/container/entitlement/route configuration |
| FrontierOptional | File Provider, App Clip, Wallet signer integration, CarPlay/PTT/Screen Time/accessory spikes | Per-feature setup and managed approval where required |

A CoreLocal build must not fail because a FrontierOptional target lacks approval. An unavailable live adapter must have an explanation and its declared fallback. Personal development, App Store distribution, Developer ID, managed capabilities, and test distribution are not interchangeable. [S37](SOURCE_INDEX.md#s37).

## Project and run entry points to implement

The initial Xcode workspace should expose clearly named schemes such as `LabMac-Core`, `LabPhone-Core`, `LabPhone-Surfaces`, `LabWatch`, and `LabTV`. These are proposed names; record actual names in a generated BUILD_STATUS document during bootstrap. Source packages are shared, but capability entitlements stay with their specific executable/extension targets.

The future `script/build_and_run.sh` stops only the known lab app, invokes the recorded Mac scheme, and opens the resulting `.app` bundle. Optional verification/log/debug flags must not bypass signing or authorization. A separate test entry point should list discovered destinations before asking for a specific device. Treat untrusted command-line input as data and avoid shell interpolation.

Planned toolchain discovery commands, which the builder must actually run on a Mac:

```sh
xcodebuild -version
xcodebuild -showsdks
xcrun swift --version
xcrun simctl list devices available
```

Do not run `xcodebuild -workspace ...` until the workspace exists. Do not print a passing build command merely because its syntax looks plausible.

## Signing and configuration

Use tracked safe defaults and ignored local overrides for development-team ID, bundle prefix, optional container identifiers, and endpoint configuration. Never commit a signing identity, provisioning profile, certificate private key, service token, real pass-signing key, or personal container export. Bundle IDs, App Groups, Keychain access groups, and CloudKit containers must be reproducibly configurable for independent developers.

Start CoreLocal with only necessary capabilities. Add entitlement keys only after verifying official documentation and the actual target's provisioning profile. An identifier string is not approval. For a failing Mac artifact, inspect `codesign -dvvv --entitlements :-` and `spctl -a -vv` before classifying the failure as compile, signing, sandbox, or distribution trust.

## Distribution lanes

Source distribution is the first public lane. A user builds with their own local configuration. Mac binary distribution may later use Developer ID signing/notarization or an appropriate store lane. iPhone/Watch/TV distribution requires an Apple-supported installation path; do not promise a universally installable unsigned IPA. A simulator build is not a public device installer.

An optional App Store/TestFlight distribution can make advanced features convenient for users, but it is not a condition of reading or building the CoreLocal examples. Foundation Models PCC eligibility is particularly constrained and cannot be assumed for every developer or every source-built install. [S07](SOURCE_INDEX.md#s07).

## Release checklist

Release from an allowlisted checkout/artifact directory, never from its parent workspace. Include only approved source, docs, original assets, license notices, and actual tested outputs. Exclude local overrides, generated model downloads, databases, device traces, signing material, and adjacent projects. Rebuild from a clean checkout, verify provenance and hashes, inspect the final archive contents, and test the documented install path on a fresh environment before calling a release ready.
