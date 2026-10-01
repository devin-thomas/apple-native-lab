import Foundation
import LabSupport
import Testing
@testable import LabCatalog

/// CORE-005: experiments are registered at compile time with their lifecycle state, fallback, and
/// source links, and the catalog can tell every lifecycle state apart.
@Suite struct ExperimentRegistryTests {
    let registry: ExperimentRegistry

    init() throws { registry = try ExperimentRegistry.bundled() }

    @Test func everyCatalogExperimentIsRegisteredExactlyOnce() {
        #expect(registry.experiments.count == 48)
        #expect(ExperimentRegistry.registrations.map(\.id) == registry.experiments.map(\.id))
        #expect(Set(ExperimentRegistry.registrations.map(\.id)).count == ExperimentRegistry.registrations.count)
    }

    /// The spec is the source of truth. A registration's fallback must be its spec's Fallback
    /// paragraph, word for word, so a spec edit that is not carried over fails here.
    @Test func everyFallbackMatchesItsSpecification() throws {
        for experiment in registry.experiments {
            let spec = try String(contentsOf: Self.repositoryRoot.appending(path: experiment.specification.relativePath), encoding: .utf8)
            #expect(experiment.fallback == Self.fallbackParagraph(in: spec), "\(experiment.id) fallback differs from its spec")
            #expect(!experiment.fallback.isEmpty)
        }
    }

    @Test func sourceLinksOpenThePublicFileOrShowItsPath() throws {
        let atlas = try #require(registry.experiment(id: "LAB-001"))
        #expect(atlas.specification.relativePath == "experiments/LAB-001-action-atlas.md")
        #expect(atlas.specification.url?.absoluteString
            == "https://github.com/devin-thomas/apple-native-lab/blob/main/experiments/LAB-001-action-atlas.md")
        #expect(atlas.tickets.map(\.relativePath) == ["tickets/LAB-001-A.md", "tickets/LAB-001-B.md"])
        #expect(atlas.tickets.map(\.title) == ["Build ticket LAB-001-A", "Qualification ticket LAB-001-B"])
        for experiment in registry.experiments {
            for link in experiment.sourceLinks {
                #expect(link.url?.host() == "github.com", "\(link.relativePath) has no public address")
                let file = Self.repositoryRoot.appending(path: link.relativePath)
                #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)), "\(link.relativePath) is missing")
            }
        }
    }

    @Test func aPathThatEscapesTheRepositoryHasNoAddress() {
        #expect(SourceLink(title: "x", relativePath: "../secrets.md").url == nil)
        #expect(SourceLink(title: "x", relativePath: "/etc/hosts").url == nil)
        #expect(SourceLink(title: "x", relativePath: "https://example.com/x").url == nil)
        #expect(SourceLink(title: "x", relativePath: "").url == nil)
    }

    @Test func theSixLifecycleStatesAreDistinguishable() {
        let states = ImplementationState.allCases
        #expect(states.map(\.rawValue) == ["specified", "spiked", "implemented", "device-verified", "release-ready", "blocked"])
        #expect(Set(states.map(\.title)).count == 6)
        #expect(Set(states.map(\.meaning)).count == 6)
        #expect(states.allSatisfy { !$0.meaning.isEmpty })
    }

    @Test func stateScopesSplitTheCatalog() {
        let total = ImplementationState.allCases.map { registry.count(in: .state($0)) }.reduce(0, +)
        #expect(total == registry.experiments.count)
        // Update only when a spec's state changes with evidence behind it.
        #expect(registry.count(in: .state(.specified)) == 25)
        #expect(registry.count(in: .state(.implemented)) == 23)
        #expect(registry.progress(for: .m1) == (live: 6, total: 6))
        #expect(registry.progress(for: .m3).live >= 1)
    }

    @Test func scopesAndSearchCombine() {
        #expect(registry.experiments(in: .milestone(.m1)).map(\.id) == [
            "LAB-001", "LAB-004", "LAB-007", "LAB-008", "LAB-010", "LAB-035",
        ])
        #expect(registry.experiments(in: .milestone(.m1), matching: "share").map(\.id) == ["LAB-007"])
        #expect(registry.experiments(in: .category("Mac"), matching: "").allSatisfy { $0.category == "Mac" })
        #expect(registry.experiments(in: .all, matching: "  ").count == 48)
        #expect(registry.experiments(in: .all, matching: "ÅCTION atlas").map(\.id) == ["LAB-001"])
        #expect(registry.experiments(in: .state(.blocked), matching: "").isEmpty)
    }

    @Test func aMissingOrUnknownRegistrationRefusesToLoad() throws {
        let catalog = try ExperimentCatalog.bundled()
        let all = ExperimentRegistry.registrations
        #expect(throws: ExperimentRegistry.LoadError.unregistered(["LAB-048"])) {
            try ExperimentRegistry(catalog: catalog, registrations: Array(all.dropLast()))
        }
        #expect(throws: ExperimentRegistry.LoadError.unknownRegistration(["LAB-900"])) {
            try ExperimentRegistry(catalog: catalog, registrations: all + [ExperimentRegistration("LAB-900", fallback: "x")])
        }
        #expect(throws: ExperimentRegistry.LoadError.duplicateRegistration("LAB-001")) {
            try ExperimentRegistry(catalog: catalog, registrations: all + [all[0]])
        }
    }

    // MARK: Helpers

    /// This file is Packages/LabFeatures/Tests/LabCatalogTests/…, four levels below the root.
    static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The first paragraph under `## Fallback`, with whitespace collapsed, as the catalog
    /// generator reads its other sections.
    static func fallbackParagraph(in spec: String) -> String? {
        guard let heading = spec.range(of: "\n## Fallback\n\n") else { return nil }
        let rest = spec[heading.upperBound...]
        let paragraph = rest.range(of: "\n\n").map { rest[..<$0.lowerBound] } ?? rest
        return paragraph.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
