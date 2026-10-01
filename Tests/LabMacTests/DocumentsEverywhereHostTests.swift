import DocumentsEverywhere
import Foundation
import LabDomain
import Testing
@testable import NativeLab

/// LAB-009 in the sandboxed Mac host: Documents Everywhere session and sidebar destination on a
/// fresh SQLite store and staging folder, never the app's real ones.
@MainActor
@Suite("Documents Everywhere host", .serialized)
struct DocumentsEverywhereHostTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DocumentsEverywhereHostTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func started() async throws -> (LabLibrary, DocumentsEverywhereSession) {
        let storeURL = folder.appending(path: LabStoreLocation.fileName)
        let staging = folder.appending(path: "staging", directoryHint: .isDirectory)
        let library = LabLibrary(locateStore: { storeURL })
        await library.start()
        try #require(library.phase == .ready)
        let session = DocumentsEverywhereSession(locateStaging: { staging })
        return (library, session)
    }

    @Test func theBrowserIsASidebarDestinationWithControlCommand2() {
        #expect(
            SidebarDestination(storageKey: SidebarDestination.documentsEverywhere.storageKey)
                == .documentsEverywhere
        )
        #expect(SidebarDestination.documentsEverywhere.title == "Documents Everywhere")
    }

    @Test func sessionOpensSamplesWithoutTheProvider() async throws {
        let (library, session) = try await started()
        await session.open(library: library)
        #expect(session.phase == .ready)
        #expect(session.entries.count == 2)
        #expect(session.providerState == .disabled)
        #expect(session.preview?.title == "Harbor note")
        #expect(session.requestProviderActivation() == .providerDisabled)
    }

    @Test func selectingTideCardUpdatesThePreview() async throws {
        let (library, session) = try await started()
        await session.open(library: library)
        session.select(ProviderItemID(rawValue: "sample.tide-card"))
        #expect(session.preview?.title == "Tide card")
        if case .previewed(let preview) = session.outcome {
            #expect(preview.title == "Tide card")
        } else {
            Issue.record("expected a previewed outcome")
        }
    }
}
