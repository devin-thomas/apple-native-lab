# Wallet Moment fixtures

Original event-pass data for [LAB-038](../../experiments/LAB-038-wallet-moment.md). Nothing here is a real ticket, venue, account, certificate, or pass-signing key. Distributed under the repository's MIT License ([ASSET_POLICY](../../docs/ASSET_POLICY.md)).

## `sample-event-pass.json`

A fictional Harbor Lantern Festival general-admission ticket. The compiled `SampleEvent.definition` in `WalletMoment` must match this file. `WalletMomentTests` refuses the fixture if it gains a signing-key or authority field.

| Key | What it holds |
|---|---|
| `pass` | The `PassDefinition`: serial, event, venue, seat, start/expiry, QR barcode (display only), update tag. |
| `readings` | Expected lifecycle titles at the three fixed clock points the tests freeze. |

No `.pkpass`, PEM, PKCS12, or WWDR material belongs in this folder.
