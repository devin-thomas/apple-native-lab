# Builder instructions

Read [START_HERE](START_HERE.md), [SPEC](SPEC.md), the relevant [ticket](TICKETS.md), and its linked experiment before changing code. This snapshot is documentation-only; do not report planned source files as existing.

## Working contract

1. Select one dependency-ready ticket. State its intended observable result, then inspect the actual toolchain and repository. Do not implement all 48 labs at once.
2. Respect the static module boundaries and capability profiles. A managed entitlement or optional dependency must not enter the default build by accident.
3. Implement the domain operation and tests before adding additional surfaces. UI, intents, extensions, and model tools call the same authorization-checked operation.
4. Probe the actual API symbol and availability in the installed SDK. Consult the linked primary source. Record any changed name or constraint in the verification ledger and affected spec.
5. Keep deterministic fixtures. Never use private accounts, customer data, personal workspaces, or real media as a shortcut to a sample.
6. Validate failures, cancellation, denied permissions, stale state, and duplicate requests. A simulator recording is not proof of camera, UWB, haptics, Watch transport, or an entitlement.
7. Record evidence honestly. Never check off a test that was not run. Preserve the smallest useful error when blocked.
8. End the change with implementation notes, the actual commands run, test results, known limitations, and the next dependency-ready ticket.

## Native engineering

Use a shared Swift package for model/operation contracts and separate platform adapters. Prefer typed identifiers, explicit error enums, dependency injection at capability boundaries, Swift concurrency with clear actor ownership, and value snapshots for cross-process views. Main-actor UI must not perform blocking file, model, or media work. Avoid detached work without cancellation ownership.

Split nontrivial features into views, models, services, and tests; do not build a giant ContentView. Use native Mac scenes, menus, and keyboard shortcuts. Use system typography, semantic color/materials, and accessible control sizes. Add custom Liquid Glass only where standard native controls do not already supply the correct treatment.

## Safety and release

No arbitrary shell invocation from app intents, model tools, imports, or network messages. No hidden cloud fallback. No authorization based solely on model output, a link, a barcode, or a display name. No secrets in source, fixtures, logs, screenshots, issue bodies, or generated release ZIPs. Do not weaken Gatekeeper, sandboxing, or platform permissions to make a demo appear successful.

The default local run entry point will be `script/build_and_run.sh` after bootstrap. It must build and open a real Mac `.app` bundle, not masquerade a raw GUI executable as a complete launch. Stop only the known lab process. The script does not exist in this planning snapshot.

Create a decision record when changing behavior, platform support, costs, external service use, or data ownership. Do not rewrite an unrelated downstream application to make the lab easier.
