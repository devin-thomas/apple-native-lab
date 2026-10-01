# LAB-003 fixtures

Original, public-safe samples for Shortcut Workbench. No accounts, personal media, or real credentials.

Bundled recipes live in `WorkbenchRecipeCatalog.bundledRecipes`. Qualification uses the fixed seed in
`Packages/LabFeatures/Tests/ShortcutWorkbenchTests/TestSupport.swift`, fixed qualification IDs and
original text in `WorkbenchQualificationTests.swift`, and the host test’s fresh SQLite store.

`original-synthetic-secret-sentinel` is an invented test value, not a credential. It is placed in
recipe titles, step details, and model-step names and values to show that no typed text leaves in an
export. Evidence hashes the fixture source or the actual exported bytes. There are no screenshots or
exported user stores in this ticket.
