# App Intents and Shortcuts contract

## Two product layers

The lab exposes a cohesive library of atomic actions with typed inputs/outputs, stable entities, useful queries, and clear error behavior. Separately, it promotes a small curated set of App Shortcuts. Plan for at most ten curated shortcuts; this is not a ten-action cap on the whole library. Curated App Shortcuts have platform-specific support; do not promise their iPhone presentation on Mac or TV. [S01](SOURCE_INDEX.md#s01), [S03](SOURCE_INDEX.md#s03).

M1 should implement approximately 8–12 meaningful domain actions, not hundreds of empty commands. Later modules can contribute actions when their underlying behavior is implemented. No numerical maximum for the atomic library is claimed; discoverability, metadata size, reliability, and actual OS behavior constrain what is sensible.

## Initial action contracts

| Action | Input | Output | Mutation policy |
|---|---|---|---|
| Find lab items | Query, collection, bounded result limit | Typed item references | Read-only |
| Get lab item | Stable item ID | Current item snapshot | Read-only; missing ID is explicit |
| Create lab item | Validated field values | Item reference + receipt | Commit once per request ID |
| Update lab item | Item ID, expected revision, patch | Updated reference + receipt | Conflict review on stale revision |
| Archive lab item | Item ID, expected revision | Receipt with permitted inverse | Confirm where required; never hard-delete implicitly |
| Export lab document | Item ID, representation | User-approved file/reference | Preview private fields; no implicit upload |
| Get session state | Session ID | Small immutable state | Read-only |
| Set session state | Session ID, desired value | Applied state + receipt | Desired value, not blind toggle |
| Preview import proposal | Staged import ID | Typed draft and validation issues | Never commits model output |
| Commit reviewed proposal | Proposal ID, revision, review grant | Item/receipt | Grant validated at commit |

These are domain-level contracts. Exact AppIntent return types, parameter presentation, dialogs, and system availability must be compiled and tested. Protected actions cannot trust a shortcut merely because it originated on the user's device.

## Recipe depth

Document recipes for share/import → inspect → transform → export; query → filter → create report; and selected media → finite export job → open result. A user may combine the lab's actions with system and other participating apps. The lab does not programmatically install personal automations, bypass confirmation, or acquire arbitrary access to another application's data.

Entity renames must not break recipes. An entity deletion returns a recoverable missing-item result. A stored reference is not a snapshot guarantee. Shortcuts Storage is not a vault for credentials; use it only for suitable non-secret workflow state with the actual platform semantics verified. [S04](SOURCE_INDEX.md#s04).

## Context, schemas, and snippets

Adopt documented schemas only for genuinely matching semantics. Associate current content using the supported entity/user-activity integration and test stale context. Provide an in-app equivalent of each interactive snippet, because Siri availability and interpretation are not guaranteed. A system presentation must never mutate an older item after the underlying selection changes. [S02](SOURCE_INDEX.md#s02), [S64](SOURCE_INDEX.md#s64).

## Testing

Pure operation tests prove behavior independent of the system. System-path tests prove actual metadata/entity/query/intent integration. Record the signing team, device/OS, exact invocation, and resulting receipt; a direct call to `perform` alone is not proof of a complete Siri or Shortcuts experience. [S05](SOURCE_INDEX.md#s05).
