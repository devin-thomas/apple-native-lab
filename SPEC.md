# Product specification

Version: 1.0 planning baseline • Research snapshot: 2026-09-29 • State: specified, not implemented

## 1. Purpose

Create an open collection of small, polished native Apple experiments that reveal capabilities ordinary apps rarely combine. Each experiment must teach through a working interaction and a visible explanation of its mechanism, not through a grid of framework names. Reusable components should be extractable without requiring the entire host app.

The product has three audiences: curious owners who want to try unusual device behavior; developers who want trustworthy examples; and commercial teams investigating an integration without prematurely building a complete product.

## 2. Product shape

A shared Swift domain core supports separate native iPhone/iPad, Mac, Watch, and Apple TV hosts. The Mac and iPhone were the first implementation targets. Watch and Apple TV smoke hosts followed (CORE-001, CORE-013, [ADR-014](docs/adr/ADR-014.md)), so every change is built and smoke-tested on all four platforms; Watch and TV experiments add their surfaces through their own tickets. Optional iPad/Pencil support is welcome but not a prerequisite for a release. Vision Pro is not required and a visionOS target is outside the initial plan.

The host contains a searchable catalog, capability/readiness information, a fixture browser, a per-experiment experience, a compact action/receipt inspector, and a settings area. A catalog entry remains useful even when its live adapter is unavailable: it explains the missing gate and offers an honest fallback where one exists.

A completed experiment includes the interaction, original fixtures, a reset path, reusable source, tests, evidence, and concise user instructions. A badge cannot substitute for implementation.

## 3. Requirements

| ID | Requirement | Acceptance anchor |
|---|---|---|
| R-01 | Public core is independent and account-free | Clean checkout, network-blocked first-run fixture path |
| R-02 | One domain operation underlies every supported entry point | UI and intent produce equivalent state and receipts |
| R-03 | Capability support is measured, not inferred from branding | Per-device OS/hardware/permission/entitlement evidence |
| R-04 | Shared content enters a safe staging area | Malformed, oversized, cancelled, and duplicate imports tested |
| R-05 | Generated output is a reviewable proposal | Invalid or unapproved output cannot mutate the store |
| R-06 | Deep integrations cannot break the baseline build | Separate targets and capability profiles |
| R-07 | Native means appropriate platform interaction | Keyboard/menus on Mac, touch on phone, glanceable Watch, focus on TV |
| R-08 | Accessibility is a release gate | Essential flows with VoiceOver, keyboard, large text, reduced motion |
| R-09 | Durable sync and live transport have distinct semantics | Offline conflict tests versus ordered-session/reconnection tests |
| R-10 | Expensive work is bounded and cancellable | Checkpoints, resource limits, failure/expiration tests |
| R-11 | Every demonstrated claim has provenance | Evidence record identifies build, device, input, result, and limitations |
| R-12 | No hidden cost, upload, purchase, or recording | Explicit route/permission/charge boundary before side effects |
| R-13 | Exports preserve meaningful structure | Native format round trips unknown fields, IDs, Unicode, and attachments |
| R-14 | Release artifacts contain only approved project material | Allowlist, license inventory, secret and metadata scans |
| R-15 | Other developers can extend the lab | Documented static module contract and a complete experiment template |

## 4. The first release: M1

Ship LAB-001 Action Atlas, LAB-004 Surface Deck, LAB-007 Share Ingress Station, LAB-008 Portable Objects, LAB-010 Typed Local Intelligence, and LAB-035 Access as a Superpower as one coherent journey. A user on an unsupported intelligence configuration can substitute manual editing and still complete the entire journey.

The first app must be more useful than a sample launcher: preserve a small local collection, allow import/export, expose typed operations, explain a failed capability probe, and provide a reliable reset of demo-owned data. No real cloud service, paid Apple entitlement, Watch, TV, or accessory is necessary to establish this core value.

## 5. Expansion milestones

M2 adds Shortcuts depth, speech/media, live status, native Mac power, local networking, and a Watch relay. M3 adds spatial/media richness, conflict-aware cloud experimentation, stronger evidence tooling, and multi-device showcases. M4 holds externally gated and optional commercial integrations, model routing, accessory experiments, and advanced extension targets. [Milestone definitions](docs/MILESTONES.md) govern the release order; a research success need not become a production release immediately.

## 6. Explicit non-goals

This is not a cross-platform toolkit, replacement operating system, unlimited background agent, arbitrary cross-app automation engine, emulator collection, or all-purpose AI assistant. It does not grant access to other apps' databases, screen contents, private files, protected media, or credentials. It does not promise every framework on every device. It does not require cloud intelligence or imply that every source build qualifies for server-side Apple services.

No production customer backend, real payment processing, production pass-signing service, or live accessory purchase is required by the initial release. Commercial samples prove bounded mechanics; shipping a business requires separate entitlement, security, policy, operations, and rights reviews.

## 7. States and definition of done

Use exactly these implementation states: `specified`, `spiked`, `implemented`, `device-verified`, `release-ready`, and `blocked`. A successful simulation can establish `implemented` for a fallback, but it cannot establish `device-verified` for its real hardware adapter. A blocked adapter may coexist with a release-ready fallback, provided the UI names the distinction.

A lab becomes release-ready only when its specific acceptance checks pass, its declared supported devices have evidence, its unavailable path is usable, its privacy and accessibility review pass, and its sources and instructions match the tested implementation. There are no passing device claims in this planning pack.

## 8. Decisions delegated to the builder

The builder may select narrowly scoped implementation details that do not alter product behavior: file decomposition, local test doubles, or a documented protocol transport choice. Changes to data loss behavior, authentication, data destinations, purchases, public scope, license, or minimum supported hardware require a recorded decision. An uncertain Apple API should be a spike, not an invented symbol.
