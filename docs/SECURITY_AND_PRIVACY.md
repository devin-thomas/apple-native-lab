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

## CI and supply chain

Public pull requests run without repository secrets, signing identities, personal data, or access to private local runners. Do not execute untrusted fork code on a persistent personal Mac. Separate unsigned compilation/testing from manual trusted signing/release. Pin optional dependencies and model descriptors; record licenses and checksums. Treat generated code and assets as reviewable inputs, not automatically trusted outputs.

## Reporting and repair

Until a maintainer configures a private security reporting channel, do not invent an email address. Contributors should avoid public disclosure of live credentials or exploit material tied to real users. When a leak is found, rotate/revoke affected credentials and investigate artifact/history exposure; deleting a file from the latest commit alone is not remediation.
