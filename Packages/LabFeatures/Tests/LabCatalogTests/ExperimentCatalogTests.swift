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
        // Implemented: LAB-001 (Mac and simulator; in-app path on a physical iPhone), LAB-004 (deck on the Mac
        // and simulator; widget and Control in the simulator), LAB-007 (paste and file-picker fallback on the
        // Mac and simulator; share extension in the simulator), LAB-008 (drag, export, and import on the Mac;
        // Files round trip in the simulator), LAB-010 (model on the development Mac and simulator, fallback on
        // both), LAB-035 (four paths on the Mac and simulator), LAB-042 (domain and adapter tests on the
        // development Mac; the running menus, Services menu, and a device were not exercised).
        #expect(catalog.experiments.filter { $0.state != .specified }.map(\.id) == ["LAB-001", "LAB-004", "LAB-007", "LAB-008", "LAB-010", "LAB-035", "LAB-042"])
        #expect(catalog.experiments.filter { $0.state == .implemented }.count == 7)
        #expect(catalog.progress(for: .m1) == (live: 6, total: 6))
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
