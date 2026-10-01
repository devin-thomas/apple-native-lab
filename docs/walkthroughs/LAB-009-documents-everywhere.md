# Documents Everywhere: a walkthrough

Documents Everywhere ([LAB-009](../../experiments/LAB-009-documents-everywhere.md)) browses two original `.anlab` samples and previews their contents without a File Provider. Adding a sample creates a user item through the same import operation as Portable Objects and leaves a receipt.

**Qualification is limited to hosted model replays on the Mac and in the iPhone simulator, plus package fixtures.** These call the actual browser session and store but do not drive a rendered screen. No physical iPhone or iPad ran. No Finder or Files Quick Look run is claimed. The SystemSurfaces iPhone build embeds a Quick Look extension; the Mac has no such extension. Sharing its preview builder does not prove the system loaded that extension.

The File Provider sources are unattached to a target. Its activation control stays disabled. A connected `ProviderSession` in a test is a fixture model, not a registered system provider. The experiment stays `implemented`.

## Try the browser

On Mac, build the real app with `script/build_and_run.sh` and choose Documents Everywhere in the sidebar or View menu (⌃⌘2). On iPhone, open its Catalog entry and choose Open Documents Everywhere. These are the implemented entry points; the qualification replays call their session model directly.

1. Select Harbor note, then Tide card. The preview shows the selected sample's title, revision, and plain-text summary. Previewing does not add anything to the collection.
2. If you want to add a sample, create a collection of your own in Action Atlas first. Demo collections cannot receive imports.
3. Choose your collection and press Add Sample to Lab. This action stages, validates, and commits the selected original sample. Inspect its app-UI receipt in the lab's receipt list.
4. Press Add Sample to Lab again. The same content is refused as already present, without another item or receipt. Qualification found that this refusal retains one staged review; the browser currently offers no Close Review action. Store preservation does not imply staging cleanup.
5. Reset Demo. The imported samples are user data, so their identities, revisions, and portable document contents remain unchanged. The bundled authoritative samples remain readable too.

Adding a sample commits immediately; this browser does not present Portable Objects' separate review sheet. To review and apply a changed file, use Portable Objects. The provider's revision tests do not establish an external editor's live behavior.

## What the fixture checks mean

| Check | Adapter and scope | Limit |
|---|---|---|
| Preview with provider disabled | `DocumentPreviewBuilder`, shared by browser and Quick Look | No system extension dispatch proved |
| Metadata edit, stale content edit, matching content edit | `ProviderSession` and `RevisionRules`: metadata moves independently; stale base conflicts without changing the mirror | In-memory mirror only; no external file coordinated |
| Eviction, repeated eviction/disconnect, reconnect | Catalog bytes compare unchanged; reconnect recreates original fixture revisions | No domain removal or system eviction |
| Denial | Read/propose-only app actor cannot adopt; no item committed | Injected operation permission, not an OS permission prompt |
| Cancellation | Task cancelled before adoption; no item or pending staging; retry creates once | No interrupted Quick Look service |
| Duplicate adoption and Reset Demo | Actual host session and fresh SQLite stores on Mac and iPhone simulator | No UI controls driven |
| Hostile input and HTML escaping | Malformed/newer-schema inputs refused; document markup appears as escaped text | Not an audit of the entire Quick Look process |

Records live in [`evidence/LAB-009/`](../../evidence/LAB-009/). Actual commands and outcomes are in [BUILD_STATUS](../BUILD_STATUS.md). The full automated gate stopped at an unrelated Mac Render That Survives test after all package suites passed; it did not reach its simulator or release-manifest steps. The separate Documents Everywhere Mac and iPhone simulator replays passed. This qualification does not claim a passing full gate. To replay the package checks:

```sh
swift test --package-path Packages/LabFeatures --filter DocumentsEverywhereTests
```

The hosted replay is `DocumentsEverywhereQualificationTests` in each host's test folder. Run it with a result bundle and export attachments using `xcrun xcresulttool export attachments`; its evidence reads provenance from the built host and hashes the actual bundled inputs.

## Privacy, rights, and accessibility

The samples in [Fixtures/LAB-009](../../Fixtures/LAB-009/README.md) are original fictional documents, not user files. Evidence contains fixture hashes, observations, and toolchain metadata. No screenshot, recording, user store, account, or raw result bundle enters the public evidence folder. No cloud account or provider connection is needed.

A static accessibility review found native labeled buttons and a collection picker, combined sample rows, selectable preview text, and a title heading. Open findings remain: sample-row labels include middle dots; Add Sample to Lab has no Mac menu command; adoption outcomes have no announcement; the iPhone primary action follows a long preview instead of being pinned; HTML uses fixed colors. No VoiceOver, Voice Control, Full Keyboard Access, large-text layout, or contrast pass was performed. See the [review matrix](../ACCESSIBILITY_REVIEW.md#documents-everywhere-lab-009).

## Remaining live gates

A static configuration finding remains: `project.yml` and the preview extension's Info.plist
do not declare `QLIsDataBasedPreview`. Apple's
[data-based preview instructions](https://developer.apple.com/documentation/quicklookui/qlpreviewprovider)
specify that key as `true`. Its effect on the iOS system dispatch has not been tested. Resolve
and regenerate target metadata before treating the compiled extension as a working preview.

Before claiming Quick Look works in the system, export an original sample, install the SystemSurfaces host, and open it in Files on the iPhone simulator with the provider absent. Observe the custom preview, not just Files' generic JSON fallback, and record the loaded extension and result. A Mac system-preview claim needs a Mac Quick Look extension first.

Before enabling a provider, the owner must decide its FrontierOptional host and target configuration. Then qualify domain registration, enumeration, materialization, cancellation, coordinated external edits, conflict handling, eviction, and disconnect against the actual extension. Verify source bytes after every failure and domain removal. Device and manual accessibility runs remain separate gates; this ticket authorizes none.
