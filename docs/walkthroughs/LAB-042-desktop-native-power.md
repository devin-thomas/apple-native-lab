# Desktop Native Power: a walkthrough

[Desktop Native Power](../../experiments/LAB-042-desktop-native-power.md) is Mac only. It imports original text notes through one authorization-checked operation, keeps them in SQLite, and offers menus, a palette, a menu-bar status, document scenes, and an allowlisted intent. It needs no account or cloud service.

## What was qualified

The package tests use an in-memory store. The Mac hosted replay uses the actual session, file-result handler, Services provider, intent runner, and a fresh SQLite store. It calls those adapters directly. The menu check reads the running application's AppKit menu items. The palette check reads an off-screen hosted SwiftUI view's accessibility tree. These are fixture checks, not a person using the system Services menu, Shortcuts, file dialog, or document scenes. No physical mobile device took part. The experiment remains `implemented`.

The [evidence](../../evidence/LAB-042/) identifies the input hash, build, adapter, and limits. Neither an automated accessibility tree nor a compiled scene is a manual accessibility or live scene qualification.

## Try the original note

1. Open View › Desktop Native Power (⌘9), or select it in the sidebar. Use a clean demo store for a publication session; never put personal text on the pasteboard for the demonstration.
2. Choose Lab › Import Fixture Note (⌥⌘N). “Harbor tally” is the original bundled note. Import commits a user item in Desktop Notes and leaves a receipt. Lab › Show Latest Receipt (⌥⌘L) opens the receipt inspector.
3. Choose View › Command Palette… (⌘K). Each command shows its menu path and shortcut. Search for “import desktop” to find File › Import Desktop Note… (⌃⌘O). Escape or Close dismisses the palette.
4. To try the file fallback, select a UTF-8 text file containing only original fixture text. The qualification invokes the selected-file handler with the bundled bytes; it does not drive the file dialog.
5. To try selected text without Services, copy original text and choose Lab › Import Selected Text (⌃⌘T). The Services declaration is “Import Selected Text”; actual discovery and delivery through another app's Services menu remain unverified. The hosted check uses a dedicated test pasteboard, never the general pasteboard.
6. Select a note and choose File › Open in New Window (Return), the toolbar button, or its context menu. Double-click is an additional path. Closing a window is intended to leave the note available. The tested close handler keeps the document and SQLite item; the native scene's close lifecycle has not been driven.
7. Read View › Desktop Status (⌥⌘9), or the menu-bar status. It counts notes and windows without quoting a note's title or body. The count represents the station's routes, and may be stale after a native window closes (see limits below).
8. Choose Lab › Reset Fixture Notes (⌥⌘R). It removes uncommitted previews only. An imported fixture is a user item and stays, as do selected-text and file imports. Global Reset Demo also preserves these user items.

Repeated imports with the same text, origin, and privacy share a stable item. Menu and intent fixture imports share the script origin, so they join one item. Importing identical bytes from a file is a different origin and creates a separate item. Reset Fixture Notes is not an erase-all-notes command.

## Automation and privacy

Run Desktop Command accepts exactly `import-fixture-note` or `show-status`. The hosted test calls the intent's runner with the registered station and observes an App Intent receipt on a fresh store. System authentication, parameter resolution, Shortcuts, and Siri have not been exercised. Arbitrary shell strings are refused before any commit; selected text is stored as data, never executed. No automation permission or scripting entitlement was added.

“Private note” controls the next import. Private notes stay listed, but their bodies are withheld after reload until explicitly opened. The restoration key omits private IDs, and a stale restoration key naming a private note is refused. This is a presentation boundary, not encryption: the note remains in the local store, and its title remains visible in the list.

## Failures and open limits

Tests cover denied model commits, cancellation before commit, empty/invalid/oversized text, unavailable storage, duplicate requests, stale private routes, fixture reset, and Reset Demo beside imported notes. A cancelled file-picker result currently displays the invalid-text error, although it writes nothing. The selected-file handler reads the entire file in a detached task before text-size validation; interrupting that read and a pre-read byte limit are not qualified. Services starts an asynchronous task; its error pointer reports missing text or a missing host immediately, not a later import failure.

Source review found no callback from `DesktopDocumentWindow` to `session.close(window:)`. Native close therefore has no demonstrated route-count reconciliation. Restoring the same ordinary snapshot repeatedly also adds station routes without deduplication. The menu-bar “Open Desktop Native Power” opens the catalog scene without selecting the desktop destination. These are current limitations to verify or repair before live qualification, not successful UI claims.

Static accessibility review finds native labeled buttons, a combined note row with a Return hint, a named private-note toggle, visible errors, and menu alternatives for every declared gesture. Palette rows include menu paths and shortcuts. The private row uses a middle dot, and session results are not explicitly announced through `LabAnnouncement`. VoiceOver, Voice Control, Full Keyboard Access, contrast, focus order, and large text remain not-run.

Rights/privacy review: all replay inputs are original bundled or test-authored fixture text. No screenshot, video, account connection, real media, personal workspace, or secret was collected. The retained JSON contains a fixture hash and observations; raw result bundles and stores are not publication artifacts. No export of user documents is part of this experiment. See [qualification](../../tickets/LAB-042-B.md) for commands and the remaining gates.
