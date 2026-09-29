# What has—and has not—been verified

Research snapshot: 2026-09-29. This pack is design work, not an Xcode/device test report.

The [source index](SOURCE_INDEX.md) distinguishes **reviewed** primary-source content from **reference** links queued for implementation research. A reviewed source supports the stated API direction only. No SDK symbol in this pack has been compiled in this environment and no physical-device test has been performed here.

## Important precision boundaries

| Tempting assumption | Specification boundary |
|---|---|
| Every new Apple device can run the same intelligence model | Probe per-device model availability. Watch/TV are not presumed local Foundation Models hosts. |
| PCC is a free general API for every developer or source install | Qualifying program, account entitlement, user availability, and permitted distribution are separate gates. [S07](SOURCE_INDEX.md#s07) |
| Ten App Shortcuts means only ten possible actions | Curated App Shortcuts and the larger App Intent action library are different products. Follow platform-specific HIG support. [S03](SOURCE_INDEX.md#s03) |
| Siri understands every arbitrary noun/action | Adopt only matching documented schemas; availability/rollout is a separate gate. In-app intent flows remain complete. [S02](SOURCE_INDEX.md#s02), [S64](SOURCE_INDEX.md#s64) |
| A Live Activity keeps any computation alive | It is a presentation surface. Work has its own permitted lifetime, checkpoint, and expiration handling. [S28](SOURCE_INDEX.md#s28), [S58](SOURCE_INDEX.md#s58) |
| CloudKit or Handoff is instant live synchronization | Durable sync, live transport, and continuation have separate contracts. [S15](SOURCE_INDEX.md#s15), [S60](SOURCE_INDEX.md#s60) |
| Wi-Fi Aware creates a universal Mac/Watch/TV mesh | Use actual runtime capabilities and separately qualify each platform. LAN is the default multi-platform transport. [S17](SOURCE_INDEX.md#s17) |
| A Watch provides unrestricted continuous motion/streaming | Normal lifecycle rules still apply; do not create fake workouts. [S19](SOURCE_INDEX.md#s19), [S43](SOURCE_INDEX.md#s43) |
| A generic Bluetooth/Wi-Fi board can do every accessory feature | ASK, BLE, UWB, Wi-Fi Aware, and vendor protocols are distinct capabilities. [S31](SOURCE_INDEX.md#s31), [S32](SOURCE_INDEX.md#s32) |
| The Apple TV model can be inferred from an informal generation description | Record the actual model; Continuity Camera's sample has a second-generation-or-later Apple TV 4K gate. [S27](SOURCE_INDEX.md#s27) |
| A shaped model response is factually correct | Guided generation constrains structure. Validation, evidence, and review remain necessary. [S06](SOURCE_INDEX.md#s06) |
| Source compilation means users can install an unsigned app anywhere | Supported device installation, signing, and distribution are separate. [S37](SOURCE_INDEX.md#s37) |

## 27-generation features

Foundation Models' 2026 material covers image inputs, a provider abstraction, richer session behavior, and evaluation tooling; those directions belong in isolated 27-generation experiments, not assumptions about every older deployment target. [S06](SOURCE_INDEX.md#s06).

Shortcuts Storage and newer system intent testing likewise have their own availability and setup. A future builder must check the concrete installed API, test actual cross-device IDs, and avoid shipping a guessed symbol based on a session transcript alone. [S04](SOURCE_INDEX.md#s04), [S05](SOURCE_INDEX.md#s05).

A background-inference entitlement or newly changed beta capability is not a baseline promise. Investigate it only in an isolated spike with current official evidence and account approval; ordinary foreground/local inference remains usable without that experiment.

## Source refresh rule

At the first implementation of a capability and before each release, record the official URL, review date, installed SDK symbol/signature, platform availability, required entitlements, demonstrated device, and remaining uncertainty. If documentation disagrees across locales or versions, retain the discrepancy and favor a minimal compile/device probe rather than guessing.
