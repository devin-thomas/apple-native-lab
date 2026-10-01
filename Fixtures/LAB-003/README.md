# LAB-003 fixtures

Original, public-safe samples for Shortcut Workbench. No accounts, personal media, or real credentials.

Bundled recipes live in `WorkbenchRecipeCatalog.bundledRecipes`. Qualification uses the fixed seed in
`Packages/LabFeatures/Tests/ShortcutWorkbenchTests/TestSupport.swift`, fixed qualification IDs and
original text in `WorkbenchQualificationTests.swift`, and the host test’s fresh SQLite store.

`original-synthetic-secret-sentinel` is an invented test value, not a credential. It is used only to
measure field-name redaction and its ordinary-text limitation. Evidence hashes the fixture source or
the actual neutral bound recipe. There are no screenshots or exported user stores in this ticket.
