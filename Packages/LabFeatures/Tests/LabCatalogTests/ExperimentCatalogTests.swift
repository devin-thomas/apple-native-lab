import Foundation
import LabSupport
import Testing
@testable import LabCatalog

@Suite struct ExperimentCatalogTests {
    let catalog: ExperimentCatalog

    init() throws { catalog = try ExperimentCatalog.bundled() }

    @Test func bundlesAllFortyEightExperiments() {
        #expect(catalog.experiments.count == 48)
        #expect(Set(catalog.experiments.map(\.id)).count == 48)
    }

    @Test func firstReleaseMatchesTheSpecification() {
        #expect(catalog.experiments(in: .m1).map(\.id) == [
            "LAB-001", "LAB-004", "LAB-007", "LAB-008", "LAB-010", "LAB-035",
        ])
    }

    @Test func everyExperimentHasTwoTicketsAndAPayoff() {
        for experiment in catalog.experiments {
            #expect(experiment.tickets == ["\(experiment.id)-A", "\(experiment.id)-B"])
            #expect(!experiment.moment.isEmpty, "\(experiment.id) has no payoff")
        }
    }

    @Test func nothingClaimsToRunWithoutEvidence() {
        // Update this expectation only when a spec's state changes with evidence behind it.
        // LAB-001 is implemented: its fallback ran on the Mac and in the iOS simulator (LAB-001-A).
        // Implemented: LAB-001 (Mac and simulator; in-app path on a physical iPhone), LAB-002 (card and typed
        // Shortcut on the Mac and compiled for the simulator; context resolution unavailable), LAB-003
        // (curated App Shortcuts and recipes in package and Mac host tests; the Shortcuts app and Siri were
        // not run), LAB-004 (deck on the Mac and simulator; widget and Control in the simulator), LAB-006
        // (opted-in search with citations and the private-note delete path in package and Mac host tests; the
        // system Spotlight index on a device was not checked), LAB-007 (paste and file-picker fallback on the
        // Mac and simulator; share extension in the simulator), LAB-008 (drag, export, and import on the Mac;
        // Implemented: Focus filter, LAB-009 (previews without the File Provider, revisions, and adoption
        // through Portable Objects in package and Mac host tests; live Quick Look, Files, and File Provider
        // were not run), LAB-031 (playback, captions, and the receipt path for playback commands in package
        // tests and the Mac, iPhone, and Apple TV hosts; no physical device, AirPlay, or Picture in Picture
        // on hardware), LAB-032 (a checkpointed render job that survives interruption in package and Mac host
        // tests; no physical device, iOS continued processing in the simulator only), Services menu, Vision
        // on a device, and a device were not exercised), LAB-043 (scheduling, and the caption fallback; no
        // microphone, and the manual exchange in package and Mac host tests; not live CloudKit, and the audio
        // and visual fallback in package and Mac host tests; no haptic hardware, and the in-app fallback in
        // package and Mac host tests; no delivered notification on a device), fallback on both), LAB-012 (a
        // fixture image to a reviewed proposal in package and Mac host tests; no camera, no physical iPhone),
        // LAB-015 (fixture executor in package tests and in the Mac host; no model loaded, no physical
        // device), LAB-016 (continuation hints in package tests; Handoff between devices was not run),
        // LAB-017 (two fixture devices, no physical device), LAB-030 (cue grammar, no physical device),
        // LAB-035 (four paths on the Mac and simulator), LAB-041 (local confirmation and a passkey simulation
        // on the Mac; the keychain record inside the sandboxed host), LAB-042 (domain and adapter tests on
        // the development Mac; the running menus, or visual search), LAB-013 (the on-device transcriber on a
        // synthesized clip on the development Mac and in the simulator, quiet hours, rip in the simulator),
        // LAB-010 (model on the development Mac and simulator, settings, the file profile.
        #expect(catalog.experiments.filter { $0.state != .specified }.map(\.id) == ["LAB-001", "LAB-002", "LAB-003", "LAB-004", "LAB-006", "LAB-007", "LAB-008", "LAB-009", "LAB-010", "LAB-012", "LAB-013", "LAB-015", "LAB-016", "LAB-017", "LAB-030", "LAB-031", "LAB-032", "LAB-035", "LAB-041", "LAB-042", "LAB-043"])
        #expect(catalog.experiments.filter { $0.state == .implemented }.count == 21)
        #expect(catalog.progress(for: .m1) == (live: 6, total: 6))
        #expect(catalog.progress(for: .m3).live >= 1)
    }

    @Test func searchMatchesTitlesAndAPIs() {
        #expect(catalog.search("action atlas").map(\.id) == ["LAB-001"])
        #expect(catalog.search("AppIntents").contains { $0.id == "LAB-001" })
        #expect(catalog.search("   ").count == 48)
    }

    @Test func rejectsDuplicateIDs() throws {
        let json = """
        {"schemaVersion":1,"sourceReview":"x","categories":["A"],"experiments":[
        {"id":"LAB-900","title":"T","category":"A","milestone":"M1","state":"specified","dependsOn":[],"moment":"m","hosts":"h","primaryAPIs":"p","tickets":[],"specPath":"s"},
        {"id":"LAB-900","title":"T","category":"A","milestone":"M1","state":"specified","dependsOn":[],"moment":"m","hosts":"h","primaryAPIs":"p","tickets":[],"specPath":"s"}]}
        """
        #expect(throws: ExperimentCatalog.LoadError.duplicateID("LAB-900")) {
            try ExperimentCatalog(data: Data(json.utf8))
        }
    }
}
