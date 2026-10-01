# Trust Desk: a walkthrough

Trust Desk ([LAB-041](../../experiments/LAB-041-trust-desk.md)) separates a stable identity, authorization to open a local fixture record, and a passkey protocol simulation. It needs no account or network connection.

## What the evidence means

The qualification replays use fresh stores, original fixture data, and scripted authorization outcomes. Hosted tests call the same session and operation as the app controls; they do not press the controls or show a biometric dialog. The Mac hosted replay uses a scoped Keychain service; the package replay uses memory. The iPhone hosted replay is simulator evidence only. None establishes successful biometry, device passcode authentication, or a system passkey ceremony. The experiment remains `implemented`.

The simulation uses `fixture.trust-desk.invalid`. It never presents AuthenticationServices' system authorization controller or contacts a relying party. Its credential is not an exportable app secret and cannot authorize the local record. Production passkeys need separate relying-party and domain configuration.

## Try the fixture

On Mac, use View › Trust Desk (⌘0), or the sidebar. On iPhone or iPad, choose Trust Desk in Catalog, then Open Trust Desk. iPad has not been qualified.

1. Read the Identity field. Rename the display name to an original label such as “North fixture”. The identifier stays the same.
2. Choose Confirm locally. This is an explicit in-app fallback, not biometry or an account sign-in. It issues a memory-only grant for 60 seconds.
3. Choose Open the sealed record. The app commits an item update and stores the fixture secret in its scoped Keychain record. Neither the note nor the receipt contains secret bytes.
4. Register simulated passkey, then Authenticate with simulated passkey. Read the simulation label and credential reference. Rename again: the credential identifier and user handle still represent the same identity.
5. Revoke authorization. A simulated passkey assertion does not re-enable opening. Confirm locally to issue another local grant.
6. Reset Desk. It removes this desk's secret and simulated credential, revokes grants, and restores the fixture title and sealed note. Other imported user items remain. Reset Demo is different: the desk record is in the user namespace, so the global demo reset leaves it alone.

Authorize with this device invokes LocalAuthentication and may show a system prompt. Successful sensor/passcode behavior requires an owner-led run. The deterministic failure replay leaves the record untouched and Confirm locally remains available. A failure also retains an earlier unexpired grant; revoke explicitly to remove it.

## Failure and review boundaries

Tests cover invalid names, no grant, expiry, revocation, scripted cancellation/unavailability, cancelled commits, unavailable storage, a stale open, duplicate opens, and scoped reset. A stale open returns a conflict receipt and writes no secret. Keychain write failure attempts to reseal the note; that compensating update is best effort, not a transaction spanning SQLite and Keychain.

Static accessibility review finds native labeled buttons and a display-name hint, combined Identity content, and a spoken receipt label. These are source findings, not a VoiceOver pass. The grant display has no timed refresh: it may show a grant after its deadline until another session refresh, although the operation checks expiry. Credential text is limited to two lines. Large text, VoiceOver, Voice Control, Full Keyboard Access, contrast, and focus order require manual review. Only opening the desk has a Mac menu shortcut; individual actions have no menu commands.

Rights/privacy review: all replay data is original fixture material; no account, real media, network ceremony, personal credential, screenshot, or exported secret was collected. Evidence contains source hashes and observed outcomes only. No screenshot or video was produced by this ticket.

See [qualification](../../tickets/LAB-041-B.md) and [evidence](../../evidence/LAB-041/). Untested live adapters and assistive-technology paths remain unverified.
