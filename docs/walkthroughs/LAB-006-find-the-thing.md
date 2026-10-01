# Find the Thing

LAB-006 remains `implemented`. The qualification replays the lexical path in the Mac host on an isolated in-memory index. It does not prove Spotlight results, Siri, semantic model retrieval, physical iPhone or iPad behavior, or a manual accessibility pass. No screenshots or recordings were captured.

## Try the original shelf

Open Find the Thing from the Mac sidebar or View menu (⌥⌘7), or use Open Find the Thing on its iPhone catalog page. Opening loads five opted-in original labels; the sixth, Unlisted packing slip, stays outside the index. Opening does not donate anything to Spotlight.

1. Search `cedar`. Lexical search returns Cedar oil vial and Cedar tray label, in that order. The answer names their stable UUIDs ending `1002` and `1001` under `A4C1E0B2-7D33-4F18-9A60-6B1F0C2D`. Citation controls select the corresponding shelf record.
2. Search `???`. The app refuses the query and says nothing was invented. Search `flaxshuttle`: no records match because the packing slip is not opted in.
3. Search `birchbark`: the original Private locker note is the single hit. Press Delete Private Note, then search again. The answer has no hits or citations. Reindex leaves the deleted fixture out.
4. Reset Fixtures restores the shelf. Other indexed records stay unchanged. This reset is distinct from the collection's Reset Demo; the index lives in memory, and a fresh app process starts a new index.
5. Donate Opted-in Records is a separate explicit system-index action. The qualification's idle donor reports that no donation occurred; this stand-in proves the unavailable message, not the live donor. To observe the real adapter, run the live host's button and separately verify system results and deletion. No such round trip is claimed here.

The answer is deterministic text assembled from actual hit IDs, not model-generated prose. The optional retriever is off by default. Its tests use scripted IDs to prove unknown IDs are discarded; they do not test an actual model. The `nativelab://find/<uuid>` link is an internal name, not a registered external URL route.

## Deletion and privacy boundary

Delete Private Note removes the note from the app search index and clears the current answer. It does not erase the bundled fixture: the shelf still lists it, and the Mac detail can still show its body through `selectedRecord`. Reset deliberately restores it. Do not use the fixture demonstration to promise secure erasure, immediate Spotlight deletion, or removal from another app's index. Live deletion is sent only by a later explicit donation.

The qualification uses original labels only, no accounts, personal documents, media, network routes, or system-wide searches. The non-shelf reset sentinel is an original index record, not a real imported document. No screenshots or export payloads containing user data were produced.

## Review and remaining gates

Static review: search, deletion, reindex, reset, and donation have labeled buttons; shelf status and retrieval method are text; citations have accessible title/ID labels; Return submits search; the Mac has a navigation shortcut. No animation is required for an operation.

Open accessibility findings: index actions have no Mac menu shortcuts; results do not post a `LabAnnouncement`; UUID-heavy citation labels can be verbose; iPhone actions may require scrolling. Manual VoiceOver, Voice Control, Full Keyboard Access, large-text layout, and contrast/settings passes are not run. These findings prevent a release-ready claim.

Evidence: [Mac host replay](../../evidence/LAB-006/find-the-thing-host-replay.json), [qualification record](../../tickets/LAB-006-B.md). Package denial, cancellation, stale revision, duplicate request, unsupported query, citation filtering, and reset/donation failure tests are listed in the completion record. A fixture pass supports `implemented` at most.
