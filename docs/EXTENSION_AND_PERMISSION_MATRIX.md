# Extension and permission planning matrix

This matrix assigns review boundaries, not preapproved entitlements. Verify exact keys and platform availability in the installed SDK and the linked source before configuration.

| Capability | Separate executable or profile? | User/account gate | Default fallback |
|---|---|---|---|
| App Intents/entity queries | Host metadata plus optional system tests | System availability; authentication for protected actions | In-app action browser |
| Widgets / Controls | Extension; SystemSurfaces profile | User adds/configures surfaces; signing capabilities | Host state deck |
| Share intake | Share extension; App Group staging where needed | User explicitly shares chosen items | File picker / paste |
| Quick Look / File Provider | Separate extension targets | Activation, file access, provider lifecycle | Host document browser |
| Local Foundation Models | Isolated adapter | Eligible device, language/region, enabled/ready assets | Manual editor / labeled parser |
| PCC / external model | CloudOptional | Program, entitlement, distribution, user eligibility, consent, quota | Local-only path |
| Camera / microphone / AR | Host capabilities | Explicit permission and selected session | Selected image/media fixture |
| Screen capture | Mac-specific target/service | System capture authorization and chosen source | File import |
| CloudKit | CloudOptional | Own container/team, iCloud account state | Local store / manual export |
| LAN / Wi-Fi Aware / UWB | Transport-specific adapters | Permission, pairing, supported hardware, lifecycle | Single-device protocol simulation |
| Watch relay | Companion app | Paired phone, app installation, current reachability | Phone control pad |
| Health / Home | Separate opt-in mode | Narrow user authorization; real purpose | Synthetic samples / home simulator |
| Wallet / App Clip | Signing/deployment-specific targets | Own configuration and any required external service | Preview / ordinary link |
| StoreKit | Local test configuration first | Separate real distribution and transaction policy | Test transaction state machine |
| CarPlay / Screen Time / PTT | Separate tiny FrontierOptional targets | Managed capability or infrastructure where required | Explicit lifecycle simulation |
| Bluetooth accessory | Optional adapter | Compatible hardware, selected pairing, permission | Software peripheral contract |

The source index and each experiment's specification remain authoritative for its actual scope. Granting one capability never implicitly enables another. Do not request all permissions on first launch.
