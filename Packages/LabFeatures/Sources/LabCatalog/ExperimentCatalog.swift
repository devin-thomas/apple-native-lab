import Foundation
import LabSupport

/// The lab's experiment registry, loaded from the JSON generated from `experiments/*.md`.
public struct ExperimentCatalog: Sendable {
    public let categories: [String]
    public let experiments: [ExperimentDescriptor]
    public let sourceReview: String

    public enum LoadError: Error, Equatable {
        case missingResource
        case unsupportedSchema(Int)
        case duplicateID(String)
        case unknownCategory(String)
    }

    private struct Payload: Decodable {
        var schemaVersion: Int
        var sourceReview: String
        var categories: [String]
        var experiments: [ExperimentDescriptor]
    }

    public init(data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schemaVersion == 1 else { throw LoadError.unsupportedSchema(payload.schemaVersion) }
        var seen = Set<String>()
        for experiment in payload.experiments {
            guard seen.insert(experiment.id).inserted else { throw LoadError.duplicateID(experiment.id) }
            guard payload.categories.contains(experiment.category) else {
                throw LoadError.unknownCategory(experiment.category)
            }
        }
        categories = payload.categories
        experiments = payload.experiments
        sourceReview = payload.sourceReview
    }

    /// The catalog bundled with this build.
    public static func bundled() throws -> ExperimentCatalog {
        guard let url = Bundle.module.url(forResource: "experiments", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try ExperimentCatalog(data: Data(contentsOf: url))
    }

    public func experiment(id: String) -> ExperimentDescriptor? {
        experiments.first { $0.id == id }
    }

    public func experiments(in category: String) -> [ExperimentDescriptor] {
        experiments.filter { $0.category == category }
    }

    public func experiments(in milestone: Milestone) -> [ExperimentDescriptor] {
        experiments.filter { $0.milestone == milestone }
    }

    /// Case- and diacritic-insensitive match on ID, title, moment, category, and APIs.
    public func search(_ query: String) -> [ExperimentDescriptor] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return experiments }
        return experiments.filter { experiment in
            [experiment.id, experiment.title, experiment.moment, experiment.category, experiment.primaryAPIs]
                .contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Progress toward a milestone: how many of its experiments claim to run.
    public func progress(for milestone: Milestone) -> (live: Int, total: Int) {
        let members = experiments(in: milestone)
        return (members.filter(\.state.isLive).count, members.count)
    }
}
