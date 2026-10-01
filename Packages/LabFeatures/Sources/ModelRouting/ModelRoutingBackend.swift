import Foundation
import LabDomain

/// What the observatory needs from the host to finish the local fallback as a real lab change.
///
/// The host implements this with `LabLibrary` / `LabDataService`, so the observatory shares the
/// domain authorization and receipt path (ADR-011). The package never holds the store.
public protocol ModelRoutingBackend: Sendable {
    /// Demo samples the local fallback may annotate, read as the model-tool proposer.
    func demoItems() async throws(ModelRoutingError) -> [LabItem]

    /// Proposes an update as the model-tool adapter. Does not commit.
    func propose(_ operation: DomainOperation) async throws(ModelRoutingError) -> OperationProposal

    /// Commits an approved update as the app UI under a new request ID.
    func commit(
        _ operation: DomainOperation,
        requestID: RequestID
    ) async throws(ModelRoutingError) -> ActionReceipt
}

/// Applies the local fallback summary to one demo sample through the domain operation spine.
public enum LocalFallbackCommit {
    /// Builds an update that appends the labeled local summary to a demo sample's note.
    public static func operation(
        for item: LabItem,
        summary: String
    ) throws(ModelRoutingError) -> DomainOperation {
        guard item.namespace == .demo else {
            throw .invalidInput("Only a demo sample can receive the observatory's local annotation.")
        }
        let addition: ItemNote
        do {
            addition = try ItemNote(summary)
        } catch {
            throw .invalidInput("The local summary is not a valid note. Nothing was changed.")
        }
        let combined = [item.note.value, addition.value]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let note: ItemNote
        do {
            note = try ItemNote(combined)
        } catch {
            throw .invalidInput("The combined note is too long. Nothing was changed.")
        }
        let changes: ItemChanges
        do {
            changes = try ItemChanges(note: note)
        } catch {
            throw .invalidInput("The update carries no changes. Nothing was changed.")
        }
        return .updateItem(id: item.id, expected: item.revision, changes: changes)
    }
}

/// Bundled fixture prompt for the observatory. Original and public-safe.
public enum RoutingFixture: String, CaseIterable, Sendable {
    case samplePrompt = "routing-sample-prompt.txt"

    public var fileName: String { rawValue }

    public var title: String {
        switch self {
        case .samplePrompt: "Sample routing prompt"
        }
    }

    public var summary: String {
        "An original short prompt used to preview outgoing fields and exercise local fallback."
    }

    public func load(from bundle: Bundle) throws -> String {
        guard let url = bundle.url(forResource: "routing-sample-prompt", withExtension: "txt") else {
            throw ModelRoutingError.unavailable("The routing fixture is not in this bundle.")
        }
        return try load(at: url)
    }

    public func load(at url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ModelRoutingError.unavailable("The routing fixture could not be read.")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ModelRoutingError.unavailable("The routing fixture is not UTF-8.")
        }
        return try RoutingPrompt.validated(text)
    }
}
