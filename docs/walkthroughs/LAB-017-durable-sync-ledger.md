# Durable Sync Ledger

This build replays two synthetic devices in one app using a private local folder. It does not connect to iCloud or call CKSyncEngine. Mac hosted-session and iPhone simulator results qualify that replay, not a live CloudKit integration. LAB-017 remains `implemented`.

**Observed limitation:** reopening the host session keeps the exported log but shows a previously live record as absent. This reproduced on Mac and iPhone simulator. The host creates a fresh in-memory store while retaining applied markers, so it skips rebuilding those edits. Export before closing if you want a document for a fresh replay; do not treat this as durable live-state restoration. The known-issue tests report this failed expectation explicitly.

## Try the replay

1. On Mac, choose View › Durable Sync Ledger (⌥⌘4). On iPhone, open the experiment from its catalog page.
2. Choose Reset Demo and confirm. Both devices start with no edit. This clears this experiment's ledger folder, including documents imported into it; it leaves the main lab collection and exported files outside that folder alone.
3. Select Device 1. Save **Field note**, **North count**. Select Device 2 and save **Field note**, **South count**, before reconnecting.
4. Reconnect. Both versions stay inspectable, with an explanation that neither device saw the other edit. Choose **Keep Device 1**. Reconnect again; both devices follow the new choice.
5. Turn **Sync profile** off. Reconnect reports that iCloud is off (the implementation uses that error for its disabled local profile). Export Document and Import Document still exchange JSON manually. A second import of the same document does not add an envelope.
6. Delete Record and confirm. Its tombstone dominates the older edit. Export the deleted ledger, reset, and import that document: the record stays deleted. Reset alone clears the local profile too; it is not a reinstall simulation.

File-dialog gestures have not been qualified here. Hosted tests call the session's export/import methods directly. The package reinstall test removes the same synthetic device's local ledger directory while retaining the file profile, then recreates it and pulls the tombstone. No app was uninstalled from a physical device. Account isolation is tested with synthetic account IDs in separate private partitions and with a refused foreign-account document, not by switching an Apple account.

## Evidence and boundaries

The [qualification record](../../tickets/LAB-017-B.md#completion-record-2026-10-01) lists commands and observations. Structured records live in [evidence/LAB-017](../../evidence/LAB-017/). Test inputs are original synthetic fixture identities, the two hostile JSON documents, and the qualification test sources; their SHA-256 digests are recorded.

No screenshots, recordings, real accounts, imported personal files, raw stores, or exported ledger contents are published. The evidence contains only source hashes and test observations. No network adapter, entitlement, external service, or data destination was added.

## Accessibility and remaining gates

Static inspection: the editor uses native Form, Picker, TextField, Button, Toggle, and confirmation dialogs. Conflict choices name the device and expose the edit as an accessibility hint. Mac device rows combine device and state into a label, and navigation has a menu shortcut. Explanations wrap and state is expressed in words rather than color alone.

This is not an accessibility pass. VoiceOver, Voice Control, Full Keyboard Access, large text, contrast, focus after resolving a conflict, and result announcements remain untested. Save, Reconnect, Import, and Export have no dedicated Mac menu shortcuts. The form requires scrolling on compact screens; no layout capture or audit ran. Import reads the chosen file synchronously on the main actor before the decoder enforces its 2 MiB byte bound; treat large/untrusted imports as an unresolved review finding.

A live qualification needs a separately implemented CloudOptional adapter/host, configured signed container, explicit owner-authorized account runs, and evidence for account changes and tombstones across actual reinstall. The current local partition tests cannot prove CloudKit account isolation. iPad, physical iPhone, companion distribution, and a 26-SDK compile are not qualified by this ticket.
