---
id: "LAB-042-A"
title: "Implement Desktop Native Power"
status: "done"
milestone: "M2"
kind: "implementation"
depends_on: ["CORE-003", "CORE-004", "CORE-005", "CORE-006", "CORE-008", "LAB-001-B", "LAB-008-B"]
---

# LAB-042-A — Implement Desktop Native Power

## Goal

Use a command palette, menu-bar status, multiwindow documents, and one deliberate automation entry point.

## Authority and scope

Read the [governing specification](../experiments/LAB-042-desktop-native-power.md) and [builder instructions](../AGENTS.md). All source paths below are intended ownership areas after bootstrap, not a claim that code already exists.

**Owned areas:** desktop-native-power module, relevant native adapter, original fixtures, domain/adapter tests.

## Implementation steps

1. Verify the exact API/platform gates and write a minimal probe for any uncertain surface
2. Use native window/menu/keyboard conventions
3. Add a Services-style selected-text import
4. Expose an allowlisted scriptable operation if appropriate
5. Restore scene state without reopening private content unexpectedly
6. Add deterministic tests for the domain operation, cancellation, invalid input, and unavailable path

## Acceptance criteria

- [x] Every gesture-only action has a discoverable alternate path. (`CommandCatalogTests.everyGestureHasADiscoverableAlternate`: each gesture names a menu path that a `DesktopCommand` also names, and every command has a menu path and a shortcut. The Mac host compiles those menus. Nobody used a running menu.)
- [x] Closing a window does not destroy its document. (`DesktopStationTests.twoWindowsCanCloseWithoutLosingTheNote` and `importingSelectedTextCommitsAReceiptAndKeepsTheNoteAfterTheWindowCloses`: closing both windows leaves the note and its lab item. Fixture path, in-memory store.)
- [x] No arbitrary shell text is executed from an intent. (`ScriptAdmissionTests.shellTextIsRefused` and `shellTextFromAScriptCommitsNothingAndIsNotRun`: `rm -rf /` and a command with a shell mark are refused before a commit, and the collection is never created. `selectedTextThatLooksLikeAShellIsStoredAndNotRun` stores that text as a note. `RunDesktopCommandIntent` takes the allowlist enum, not a string. No process API is called.)
- [x] Fallback is usable: Standard menu command and file import. (`aFileImportIsTheMenuFallback`: the bundled fixture bytes commit as a file-import note through the app UI, and File › Import Desktop Note… is that command's menu path. The file dialog itself was not opened.)
- [x] Sensitive operations share the domain authorization/receipt path. (Imports commit `createItem` through `OperationService`. Selected text and the file import record an app-UI receipt. `theAllowlistedIntentImportsTheFixtureAsAnAppIntent` records an App Intent receipt. `aModelToolCannotCommit` is refused and writes nothing. A second entry point joins the existing item.)

## Validation and evidence

Run the narrowest unit/adapter tests that prove the acceptance criteria. Record actual commands, input IDs, observed output, and failure cases. Add a physical-device result only when the live adapter was tested on that device; keep simulated and unavailable paths explicit. Never check a criterion merely because the specification describes it.

## Failure, rollback, and limits

Retain existing data and the last usable fallback. New behavior must be disabled cleanly without deleting unrelated state. No publication, purchase, credential creation, account connection, or production-system mutation is authorized by this ticket unless explicitly described with its own consent boundary.

**Explicit boundary:** Desktop scripting is a separate permission boundary, not a cross-platform universal ability.

**Research:** [S57](../docs/SOURCE_INDEX.md#s57), [S38](../docs/SOURCE_INDEX.md#s38).

## Completion note

Record changed files, actual tests run, evidence location, unresolved external gates, and any specification correction. Leave status `planned` until work begins; use `blocked` with the exact reason when an external prerequisite is missing.

## Completion record (2026-09-30)

LAB-042's spec now claims `implemented`. The domain contract ran as package tests against an in-memory store. The Mac host compiled. Nothing here was used from a running menu, a Services menu, a file dialog, or a device.

**Persisted shape.** A note is a user item in Desktop Notes (`04200000-0000-4000-8000-000000000042`). Extras are `{"desktop":{"origin":…,"privacy":…}}`, recorded in [DATA_CONTRACTS](../docs/DATA_CONTRACTS.md#desktop-notes). The scene key stores ordinary document IDs only.

**Changed:**

- `Packages/LabFeatures`: the `DesktopNativePower` product and target (new), depending on LabDomain, with `sample-desk-note.txt`. It holds `DesktopCommand`, `DesktopDocument`, `DesktopWindow`, `SceneSnapshot`, `ScriptAdmission`, `DesktopStation`, `DesktopBackend`, and, on macOS, `RunDesktopCommandIntent`. Tests: `DesktopNativePowerTests` (new), 24 tests in 3 suites.
- `Apps/Mac/Desktop/` (new): `DesktopPowerSession`, `DesktopServiceProvider`, and `DesktopPowerColumns` (list, detail, palette, document window, menu-bar menu).
- Hooks, one case each:
  - `MainWindowState` has the destination.
  - `MainWindow` has the columns, the search prompt, and the desktop chrome.
  - `SidebarView` has the row.
  - `LabCommands` has View › Desktop Native Power (⌘9), Command Palette… (⌘K), Desktop Status (⌥⌘9), File › Import Desktop Note… (⌃⌘O), File › Open in New Window (Return), and the Lab menu's Import Selected Text (⌃⌘T), Import Fixture Note (⌥⌘N), and Reset Fixture Notes (⌥⌘R).
  - `ExperimentDetailView` opens the destination on macOS.
  - `LabMacApp` owns the session, the menu-bar extra, and the document window group.
  - `ActionAtlasHost` includes `DesktopNativePowerIntentsPackage` on macOS only.
- `project.yml` and the regenerated project: LabMac links `DesktopNativePower`. iPhone, Watch, Apple TV, and LabPhoneSurfaces do not. `Apps/Mac/Info.plist` declares `NSServices` (`importSelectedText`, `public.utf8-plain-text`). No new entitlement. `xcodegen` 2.46.0 ran on the checkout machine; research does not have `xcodegen`.
- `Tests/LabMacTests/ActionAtlasHostTests.swift` expects 12 actions, including `RunDesktopCommandIntent`.
- `experiments/LAB-042-desktop-native-power.md`: `state: implemented` and implementation notes. The Fallback paragraph is unchanged. The catalog JSON was regenerated.
- [Installed SDK ledger](../docs/VERIFICATION_BOUNDARIES.md#desktop-scenes-and-services-lab-042), short notes under [S38](../docs/SOURCE_INDEX.md#s38) and [S57](../docs/SOURCE_INDEX.md#s57), and rows in [BUILD_STATUS](../docs/BUILD_STATUS.md).

**Implementation steps:**

1. **Probe.** The installed macOS 27.0 SDK was read for `MenuBarExtra`, `WindowGroup.init(id:for:content:)`, and `NSApplication.servicesProvider`. Findings are in the ledger. Both SwiftUI symbols are below the 26.0 floor, so neither is behind `LAB_SDK_27`.
2. **Menus and windows.** Every command names a menu path and a shortcut. Double-click and the menu-bar status each have that menu path. Closing a window drops the window, not the document.
3. **Selected text.** The Services provider reads a pasteboard string and imports it. It does not treat the string as a command. The system Services menu was not invoked.
4. **Allowlist.** The intent's parameter is `AllowlistedDesktopCommand` (`import-fixture-note`, `show-status`). Any other script text, including shell marks, a slash, or internal whitespace, is refused before a commit.
5. **Scene restore.** A private note can be open in the session that imported it. Its id is left out of the storage key. A restored snapshot that names it does not open it. Reset Fixture Notes removes the uncommitted fixture preview only.
6. **Tests.** The domain operation, cancellation (`aCancelledImportCommitsNothing`), invalid input (`invalidTextCommitsNothing`), and the unavailable path (`anUnavailableStoreCommitsNothing`).

**Not run:**

- A running Mac app: menus, the command palette, the menu-bar extra, the file dialog, the document window, and the system Services menu.
- Shortcuts, Siri, VoiceOver, Voice Control, and Full Keyboard Access.
- A physical device. iPhone, Watch, and Apple TV do not link this product.
- A 26-SDK compile.
