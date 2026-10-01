# Point, Inspect, Propose

LAB-012 remains `implemented`. Qualification uses original fixtures and fresh local stores. The Mac and iPhone simulator hosted tests call the session and backend in the built apps; they do not press controls in a window. No physical iPhone, iPad, camera, live model description, or system visual-search invocation was tested. The iPhone session replay passed on an iPhone 18 Pro simulator, iOS 27.0 (24A434); it is not a touch or picker test.

Open Point, Inspect, Propose from the Mac sidebar or its catalog page. On iPhone the catalog page offers Open Point, Inspect, Propose. The following is a public-safe replay recipe; the hosted tests exercise its session methods rather than the visible controls.

1. Choose Replay Fixture. It loads the green/blue swatch, not a photograph. The original source file is 115 bytes with SHA-256 `5878b4eb086241d408b0ab74bcb3d48c42b035fa93d1766b5d3a43ee9f4a7105`.
2. Type “Original swatch” in Title and “Green and blue, typed by the reviewer” in Note. Choose Use These Fields. The source says “Manual fields (not a model)”; no item or receipt has been written yet.
3. Review both fields and choose Apply. The record belongs to Inspections, in the user namespace, with an app-UI receipt. Its note retains the image hash and replay origin. The image bytes are not stored in that item.
4. Reset Demo. The saved inspection remains unchanged. Reset restores the demo namespace; it does not clear records a person applied, even from this fixture.

The iOS build processes the PNG into 138 bytes, SHA-256 `a4ef56265ebd8066a5c137987ac43445f2973879897e094389b03d33f2c23e2b`. Provenance follows the bytes the app consumes, so the iPhone record need not carry the source-file hash.

Read Text uses Vision on the chosen bytes. The bundled swatch has no text: use the fields when recognition offers none. Package adapter tests draw their own text and QR images. The qualification's uncertain text and action-looking barcode are scripted readings of the swatch, not claims that Vision found text or a barcode in it. A barcode becomes text in the note, never an action or permission. Low-confidence text stays editable and marked uncertain, including after a person changes the description.

Describe on this Device needs the 27-generation image attachment API and a ready on-device model. A scripted model-unavailable result proves that the manual route still saves; it does not establish actual model readiness. The visual-search intent takes labels only and proposes a record. Whether the system offers or invokes it remains unverified.

The tests refuse empty, oversized, and unsupported image headers; an empty title; and a model-tool commit. Inspection cancellation and time limits write nothing. A stale approval whose item ID has been created elsewhere cannot overwrite that item. Retrying the same approval returns the same receipt. A fresh approval or another Apply is a new create operation, so matching image hashes do not deduplicate separate records.

Privacy review: the module has no upload or URL-opening route; visual search is off by default. The synthetic “Sample cabinet code 4419” is original test text, not a credential. Apply deliberately stores recognized text in a local item note, which may later be exported by another experiment after a separate user action. Local by default is not a promise that downstream exports redact that note. No external accounts, customer images, or real private text were used. No screenshots, recordings, or export ZIPs were produced for this ticket.

Accessibility review is source-only: Title and Note have visible labels, essential actions use standard buttons, uncertainty is written in words, and Replay Fixture/Read Text/Describe/Apply have hints. Manual VoiceOver, Voice Control, Full Keyboard Access, large-text layouts, and an accessibility audit remain not-run. Findings: no dedicated Mac menu shortcuts for this flow; Apply is inside the scrolling Form rather than pinned on iPhone; status text has no explicit announcement; file reading is synchronous on the main actor; leaving the screen does not explicitly cancel its button tasks. These are follow-ups, not passing accessibility or cancellation claims.

See the [qualification record](../../tickets/LAB-012-B.md), [evidence](../../evidence/LAB-012/), and [installed SDK ledger](../VERIFICATION_BOUNDARIES.md#point-inspect-propose-lab-012). Before promotion, an owner must exercise the selected-image/manual route on a physical iPhone, separately qualify any live model and system visual-search claims, and complete the assistive-technology passes. Camera capture is not implemented in this build.
