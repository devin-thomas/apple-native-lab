import Foundation
import LabDomain
import Testing
@testable import NativeLab

/// ADR-013 in the host: destructive changes need a grant, issued only for a named authority and
/// revoked after the commit. Each test uses a fresh store in the container's temporary folder.
@MainActor
@Suite struct LabGrantHostTests {
    let storeURL: URL

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "LabGrantHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appending(path: LabStoreLocation.fileName)
    }

    @Test func firstRunSeedCannotResetADemoThatAlreadyHasData() async throws {
        let seed = try DemoSeedResource.load().seed
        let service = try await LabDataService.open(at: storeURL)
        _ = try await service.perform(.resetDemo(seed: seed), requestID: RequestID(), authority: .firstRunSeed)

        await #expect(throws: OperationError.self) {
            try await service.perform(.resetDemo(seed: seed), requestID: RequestID(), authority: .firstRunSeed)
        }
    }

    @Test func aUserActionCanResetTheDemoAgain() async throws {
        let seed = try DemoSeedResource.load().seed
        let service = try await LabDataService.open(at: storeURL)
        _ = try await service.perform(.resetDemo(seed: seed), requestID: RequestID(), authority: .firstRunSeed)
        let receipt = try await service.perform(.resetDemo(seed: seed), requestID: RequestID(), authority: .userAction)
        #expect(receipt.conflict == nil)
    }

    @Test func libraryActionsStillCommitThroughGrants() async throws {
        let url = storeURL
        let library = LabLibrary(locateStore: { url })
        await library.start()
        let item = try #require(library.collections.first?.items.first)
        let archived = await library.setArchived(item, true)
        #expect(archived?.receipt.conflict == nil)
        #expect(library.failure == nil)
        let reset = await library.resetDemo()
        #expect(reset != nil)
        #expect(library.failure == nil)
    }
}
