# Start here

## For someone who wants to play

This particular package is a plan, not an app download. The first usable release is milestone M1. Once implementation exists, the intended entry point is a native Mac or iPhone app with bundled examples, a capability dashboard, and a single Reset Demo action. No cloud sign-in is part of the first-run path.

Browse [the catalog](experiments/INDEX.md) to choose a payoff rather than a framework. Every catalog entry identifies its real device requirements and its manual or simulated alternative. Simulations are useful demonstrations, but they are never presented as physical-device proof.

## For the first builder

1. Read [AGENTS.md](AGENTS.md), [SPEC.md](SPEC.md), [architecture](docs/ARCHITECTURE.md), and [build rules](docs/BUILD_AND_DISTRIBUTION.md).
2. Execute [CORE-001](tickets/CORE-001.md) through the dependency-ready foundation work. Record the actual Xcode version, SDK availability, and deployment targets before writing platform-specific adapters.
3. Implement Action Atlas and Portable Objects as the initial domain and interchange spine. Establish accessibility while the first components are still small.
4. Add Share Ingress, Typed Local Intelligence, Surface Deck, and the Access as a Superpower demonstration. A model-unavailable device must still complete the flow.
5. Close [CORE-012](tickets/CORE-012.md) only after the complete M1 journey is proven. Complete [CORE-011](tickets/CORE-011.md) before advertising a downloadable release.

The precise dependency graph in [TICKETS.md](TICKETS.md) is authoritative. Number order is a navigation aid, not permission to ignore dependencies.

## First integrated demonstration

Import the bundled note about a fictional collection item. The share inbox preserves its origin. The user inspects an extraction proposal or edits the same fields manually. A deterministic operation commits exactly one record and returns an undo receipt. That record is visible in the app and an action/entity query. A user-added widget reflects an explicitly chosen non-sensitive session state. VoiceOver and keyboard users complete the same essential work.

The payoff must be real before the decoration becomes elaborate. A named LabDocument can move between the app and Files; no production API, paid model route, second device, or automatic system setup is required.

## What to read next

For a Mac-first implementation, use [Native UX](docs/NATIVE_UX.md). For deeper capabilities, use [Milestones](docs/MILESTONES.md). For source confidence and version-sensitive claims, use [Verification boundaries](docs/VERIFICATION_BOUNDARIES.md).

## Dependency-ready navigation

A generated [execution order](docs/EXECUTION_ORDER.md) provides one valid starting sequence. Parallel work is safe only when all declared prerequisites are satisfied.
