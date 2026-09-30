import Foundation
import LabDomain
import Synchronization
@testable import SurfaceDeck

/// The host's rules over an in-memory store: `GrantAuthorizationPolicy`, the app UI and App
/// Intent actors, and a record of every commit and every settled outcome, the way the hosts'
/// `LabDataService` composes the real store.
final class ServiceSessionBackend: SessionBackend {
    static let appUI = ActorScope(adapter: .appUI, grants: Set(Permission.allCases))
    static let appIntent = ActorScope(adapter: .appIntent, grants: Set(Permission.allCases))

    let store = InMemoryOperationStore()
    let ledger = GrantLedger()
    let service: OperationService
    private let log = Mutex<(commits: [(SessionEntryPoint, SessionSurface, ActionReceipt)], settled: [SessionOutcome])>(([], []))

    init() {
        service = OperationService(store: store, policy: GrantAuthorizationPolicy(ledger: ledger))
    }

    static func actor(_ entryPoint: SessionEntryPoint) -> ActorScope {
        switch entryPoint {
        case .appUI: appUI
        case .appIntent: appIntent
        }
    }

    func session(via entryPoint: SessionEntryPoint) async throws(SurfaceDeckError) -> LabSession? {
        do { return try await service.findSession(SurfaceDeck.sessionID, as: Self.actor(entryPoint)) } catch { throw .refused(error) }
    }

    func commit(
        _ operation: DomainOperation, requestID: RequestID, via entryPoint: SessionEntryPoint, surface: SessionSurface
    ) async throws(SurfaceDeckError) -> ActionReceipt {
        let receipt: ActionReceipt
        do {
            receipt = try await service.perform(OperationRequest(id: requestID, operation: operation, actor: Self.actor(entryPoint)))
        } catch {
            throw .refused(error)
        }
        log.withLock { $0.commits.append((entryPoint, surface, receipt)) }
        return receipt
    }

    func didSettle(_ outcome: SessionOutcome, surface: SessionSurface) async {
        log.withLock { $0.settled.append(outcome) }
    }

    var commits: [(entryPoint: SessionEntryPoint, surface: SessionSurface, receipt: ActionReceipt)] {
        log.withLock { $0.commits.map { ($0.0, $0.1, $0.2) } }
    }

    var settled: [SessionOutcome] { log.withLock { $0.settled } }

    var link: SurfaceDeckLink { SurfaceDeckLink(backend: self, openDeck: {}) }

    /// The stored session, read as the app UI.
    func stored() async throws -> LabSession? {
        try await service.findSession(SurfaceDeck.sessionID, as: Self.appUI)
    }
}

/// A folder removed when the value is released.
final class TemporaryFolder: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "SurfaceDeckTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var snapshotFile: SessionSnapshotFile { SessionSnapshotFile(url: SessionSnapshotFile.location(inGroupContainer: url)) }
}

extension Revision {
    static func r(_ value: Int) -> Revision { Revision(rawValue: value)! }
}

/// The repository root, found from this source file.
enum Repository {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // SurfaceDeckTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LabFeatures
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root

    static func swiftFiles(in relativeFolder: String) throws -> [URL] {
        let folder = root.appending(path: relativeFolder, directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        return names.filter { $0.hasSuffix(".swift") }.sorted().map { folder.appending(path: $0) }
    }
}
