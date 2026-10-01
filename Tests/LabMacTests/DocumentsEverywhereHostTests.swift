import DocumentsEverywhere
import Foundation
import LabDomain
import Testing
@testable import NativeLab

/// LAB-009 in the sandboxed Mac host: Documents Everywhere session and sidebar destination.
@MainActor
@Suite("Documents Everywhere host", .serialized)
struct DocumentsEverywhereHostTests {
    @Test func theBrowserIsASidebarDestinationWithCommand9() {
        #expect(
            SidebarDestination(storageKey: SidebarDestination.documentsEverywhere.storageKey)
                == .documentsEverywhere
        )
        #expect(SidebarDestination.documentsEverywhere.title == "Documents Everywhere")
    }

    @Test func sessionOpensSamplesWithoutTheProvider() async throws {
        let library = LabLibrary()
        await library.start()
        try #require(library.phase == .ready)

        let session = DocumentsEverywhereSession()
        await session.open(library: library)
        #expect(session.phase == .ready)
        #expect(session.entries.count == 2)
        #expect(session.providerState == .disabled)
        #expect(session.preview?.title == "Harbor note")
        #expect(session.requestProviderActivation() == .providerDisabled)
    }

    @Test func selectingTideCardUpdatesThePreview() async throws {
        let library = LabLibrary()
        await library.start()
        try #require(library.phase == .ready)

        let session = DocumentsEverywhereSession()
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
