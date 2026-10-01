# LAB-040 Commerce Without Tricks fixtures

Original, neutral products; no App Store listings or private account data.

| Product ID | Display name | Type |
|---|---|---|
| `lab.commerce.field-notebook` | Field Notebook Unlock | Non-consumable test unlock |
| `lab.commerce.sample-compass` | Sample Compass Overlay | Non-consumable test unlock |

`Commerce.storekit` is a local StoreKit Testing configuration. No default scheme enables it. The app uses `CommerceFixture` and the explicitly labeled transaction-state simulator, with history limited to that screen's session. Every price and term says simulated / no real charge.

`ConfigurationProbe.swift` is outside all app and package targets. Run `labr <worktree> 'Fixtures/LAB-040/check_configuration.sh'` to compile an isolated XCTest bundle in `build/LAB-040/` and run it with developer framework/library search paths. It constructs `SKTestSession(contentsOf:)` and requests no purchase. The driver also fails on StoreKitTest service errors, because an empty history after a refused fetch is not proof. On this runner, configuration saving and transaction fetching were refused with `SKServiceErrorDomain` code 2 / underlying `SKInternalErrorDomain` code 4. A standalone executable aborts without the XCTest runtime. Local StoreKit transaction testing remains blocked here pending investigation in an application-hosted test; the app fallback is independent of that gate.

Reset Commerce updates only the two product records' notes through the shared operation service; saved receipts and unrelated records remain. See [ADR-018](../../docs/adr/ADR-018.md).
