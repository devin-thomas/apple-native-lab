# Security and privacy

## Data classification

Public fixtures are synthetic/original and redistributable. User-imported data is private by default. Credentials, authorization grants, raw room geometry, health samples, recordings, and model input are sensitive and never become public fixtures or telemetry automatically. No analytics or crash-reporting SDK is part of the baseline; use local, redacted diagnostics and an explicit user-selected export.

Reset Demo touches only a fixture namespace. Delete My Imported Data operates on the selected user namespace after a preview. Account switching must detach caches and indexes belonging to the previous account; do not display stale private data during a reconnect.

## Threat model

Assume hostile text inside shared pages, malformed archives, forged deep links, malicious QR codes, oversized media, untrusted peers, replayed commands, stale widgets, prompt injection, and misleading model output. A trusted network name or familiar display name is not identity. An imported instruction never changes the agent's or application's permissions.

An app intent, visual-search match, model tool call, or shortcut is not an authorization bypass. Authentication, expected revision, capability scope, and destructive-action policy are checked by the same application service used by the UI. Do not let a model synthesize executable operation names or arbitrary file paths.

## Consent boundaries

Request camera, microphone, photo, local network, HealthKit, HomeKit, notifications, screen capture, or other permissions at the point of explicit use. Explain the purpose before the system prompt. On denial, show the fallback; do not repeatedly ask or open Settings automatically.

Recording has a visible start/stop state and a selected source. Cloud inference has a route/data preview and explicit permission separate from local generation. Purchases and external writes have their own confirmation policy. Presentation flourishes never grant new permissions.

## Live transport

Pair explicitly. Prefer proven platform cryptography and authenticated transport, with a cryptographically strong peer identity and a verifiable short-code/QR confirmation ceremony. Do not design a homegrown encryption protocol or treat a six-digit code alone as encryption. Bind the verified identity to the transport, rate-limit pairing attempts, expire invitations, and make revocation observable.

Peers receive only negotiated roles and allowlisted operations. Bound message size, queue length, concurrent jobs, resource cost, and retry count. Reject replay or cross-session messages. A lost/revoked peer cannot remain authorized through a cached socket. Keep the first implementation LAN-only; no automatic port forwarding, public listener, or unattended remote execution.

## Files, model input, and logs

Enforce the [data contract](DATA_CONTRACTS.md) before loading imported content into a model or media pipeline. Stage inside an app-owned directory and adopt atomically. Resolve security-scoped access only for the chosen local resource, and release it when done. Never distribute bookmarks as portable access tokens.

Tools available to a language-model session have narrow typed inputs and output-size bounds. Baseline tools read approved local records or create drafts. Human review is mandatory before sensitive mutation. Model structure constraints do not establish truth. [S06](SOURCE_INDEX.md#s06).

Default OSLog/diagnostic events contain experiment IDs, phases, error categories, durations, and counts—not raw prompts, transcript text, file paths, names, tokens, room data, or health values. An optional detailed local diagnostic mode must identify what it captures and provide a purge action. Export previews must redact filenames and embedded metadata, not only visible screen labels.

### How CORE-006 enforces this

**Logging.** Lab code logs only through `DiagnosticsLog` in `Packages/LabDomain/Sources/LabDomain/Diagnostics/`. A `DiagnosticEvent` has only these fields: a phase, count names and values, a ticket or experiment ID that must match its pattern, an outcome, an error category, a duration, and a time to the second. Phase and count names can be made only from string literals. No field accepts runtime text. An error is recorded by its category alone, never by its description, which for system errors often contains a path. `OSLogDiagnosticSink` writes each event as one line marked public, which is safe because the line cannot hold private text. A test fails if any host or package source outside that folder calls `print`, `NSLog`, `os_log`, `Logger`, or a standard stream. The in-memory log keeps the most recent 500 events and has a purge action. There is no detailed diagnostic mode yet.

**Export.** A person chooses what to export: subjects, outcomes, and whether to include durations and counts. `DiagnosticExportPreview` computes the complete file first. The person reviews its text and chooses where to save it, and the saved file is exactly those bytes. Times are rounded down to the minute and sequence numbers are dropped. The file is plain JSON with no device, account, or embedded metadata. Nothing is sent anywhere.

**Staging.** A share extension, or the host's paste and file-picker fallback, writes an import to `StagingArea` (`Packages/LabStaging`) and finishes. Each import is first written to its own incoming folder, then moved into place with one exclusive rename, so a cancelled, failed, or interrupted import leaves nothing waiting. Folders a stopped process left behind are swept after an hour. Before the app adopts an import, it validates it again from disk. It refuses symbolic links, hard links, unlisted or missing files, and changed bytes or records, and sets the import aside in quarantine, where it cannot block the next one. The quarantine keeps only the rejection code. Rejections name a position and a reason, never a file name or content. New files use `completeUnlessOpen` data protection on iOS, watchOS, and tvOS.

**Grants and instructions.** Adopting an import needs a short-lived grant for a new item in the collection the person chose, checked at commit ([DATA_CONTRACTS](DATA_CONTRACTS.md#identity-and-operations)). An import becomes exactly one new item. Nothing in its content selects the operation, the target, the adapter, or a permission, and nothing in it can create a grant. A staging record that carries a scope, grant, or operation field is refused.

## CI and supply chain

Public pull requests run without repository secrets, signing identities, personal data, or access to private local runners. Do not execute untrusted fork code on a persistent personal Mac. Separate unsigned compilation/testing from manual trusted signing/release. Pin optional dependencies and model descriptors; record licenses and checksums. Treat generated code and assets as reviewable inputs, not automatically trusted outputs.

## Reporting and repair

Until a maintainer configures a private security reporting channel, do not invent an email address. Contributors should avoid public disclosure of live credentials or exploit material tied to real users. When a leak is found, rotate/revoke affected credentials and investigate artifact/history exposure; deleting a file from the latest commit alone is not remediation.
