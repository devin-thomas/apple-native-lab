import Foundation
import LabSupport

/// The experiments this build registers, each joined with its spec-generated descriptor.
///
/// Loading checks that the catalog and the compiled registrations name exactly the same
/// experiments, so a spec without a registration, or a registration without a spec, fails loudly
/// instead of silently dropping an entry. Filtering and ordering live here rather than in a view,
/// so every host shows the same results for the same query.
public struct ExperimentRegistry: Sendable {
    public enum LoadError: Error, Equatable {
        /// Experiments in the catalog that the build does not register.
        case unregistered([String])
        /// Registrations that name no experiment in the catalog.
        case unknownRegistration([String])
        case duplicateRegistration(String)
    }

    public let categories: [String]
    /// Every experiment, in catalog order.
    public let experiments: [RegisteredExperiment]
    public let sourceReview: String

    public init(
        catalog: ExperimentCatalog,
        registrations: [ExperimentRegistration] = ExperimentRegistry.registrations
    ) throws(LoadError) {
        var byID: [String: ExperimentRegistration] = [:]
        for registration in registrations {
            guard byID.updateValue(registration, forKey: registration.id) == nil else {
                throw .duplicateRegistration(registration.id)
            }
        }
        let catalogIDs = Set(catalog.experiments.map(\.id))
        let unregistered = catalog.experiments.map(\.id).filter { byID[$0] == nil }
        guard unregistered.isEmpty else { throw .unregistered(unregistered) }
        let unknown = registrations.map(\.id).filter { !catalogIDs.contains($0) }
        guard unknown.isEmpty else { throw .unknownRegistration(unknown) }

        categories = catalog.categories
        experiments = catalog.experiments.map { RegisteredExperiment(descriptor: $0, registration: byID[$0.id]!) }
        sourceReview = catalog.sourceReview
    }

    /// The catalog bundled with this build, joined with the compiled registrations.
    public static func bundled() throws -> ExperimentRegistry {
        try ExperimentRegistry(catalog: ExperimentCatalog.bundled())
    }

    public func experiment(id: String) -> RegisteredExperiment? {
        experiments.first { $0.id == id }
    }

    /// The experiments in `scope` that match `text`, in catalog order. Text matching is case- and
    /// diacritic-insensitive over ID, title, payoff, category, and APIs; blank text matches all.
    public func experiments(in scope: CatalogScope, matching text: String = "") -> [RegisteredExperiment] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return experiments.filter { experiment in
            scope.contains(experiment) && (needle.isEmpty || Self.matches(experiment, needle))
        }
    }

    /// How many experiments are in `scope`, ignoring any search text.
    public func count(in scope: CatalogScope) -> Int {
        experiments.count(where: { scope.contains($0) })
    }

    /// Progress toward a milestone: how many of its experiments claim to run.
    public func progress(for milestone: Milestone) -> (live: Int, total: Int) {
        let members = experiments(in: .milestone(milestone))
        return (members.count(where: \.state.isLive), members.count)
    }

    private static func matches(_ experiment: RegisteredExperiment, _ needle: String) -> Bool {
        [experiment.id, experiment.title, experiment.moment, experiment.category, experiment.primaryAPIs]
            .contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// A slice of the catalog a person can browse: everything, one milestone, one category, or one
/// lifecycle state.
public enum CatalogScope: Hashable, Sendable {
    case all
    case milestone(Milestone)
    case category(String)
    case state(ImplementationState)

    public var title: String {
        switch self {
        case .all: "All Experiments"
        case .milestone(let milestone): "\(milestone.rawValue) · \(milestone.title)"
        case .category(let category): category
        case .state(let state): state.title
        }
    }

    public func contains(_ experiment: RegisteredExperiment) -> Bool {
        switch self {
        case .all: true
        case .milestone(let milestone): experiment.milestone == milestone
        case .category(let category): experiment.category == category
        case .state(let state): experiment.state == state
        }
    }
}

extension ImplementationState {
    /// What the state promises, in one sentence a catalog can show beside its badge (SPEC §7).
    public var meaning: String {
        switch self {
        case .specified: "Described in its spec. Nothing runs yet."
        case .spiked: "An API probe or prototype exists. It is not a working feature."
        case .implemented: "Runs in this build. Not yet proven on a physical device."
        case .deviceVerified: "Recorded evidence shows it working on a physical device."
        case .releaseReady: "Passed its acceptance, device, privacy, and accessibility checks."
        case .blocked: "Waiting on an external prerequisite. Its fallback may still run."
        }
    }
}
