# Typed Local Intelligence notes (LAB-010)

Original, synthetic notes written for this project and distributed under its MIT License. Nothing here came from a person or an import. Both hosts bundle the two `.txt` files as resources (`project.yml`), and `IntelligenceFixture` in `Packages/LabFeatures/Sources/TypedIntelligence` names them.

| File | SHA-256 | What it tests |
|---|---|---|
| `intelligence-ambiguous-note.txt` | `86ecae7623d604f22613834ded5c021958c4b2a9b2cb064a54d158c9aa58d8ae` | "The blue one" could be the cobalt or the verdigris swatch; the note also names the vellum and the amber, and suggests a rename in quotes. |
| `intelligence-injected-note.txt` | `3c698a5d914355d243288491422b45bdaf9d8bf3b5ec8b2229a2c70554070019` | One real observation about the kraft card, then text that imitates a system override, asks for archives, a reset, and a destructive grant, and offers a fake approval token. |

The notes refer to samples in [`demo/seed.json`](../demo/seed.json) by their titles. They are data: an extractor may only propose one edit to one offered sample, and nothing changes until a person applies it.

`PrivacyAndRouteTests.theFixturesAreTheFilesTheEvidenceNames` pins both hashes. Change a note only together with the evidence that cites it.
