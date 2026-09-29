import Foundation
import LabSupport
import Testing
@testable import NativeLab

/// CORE-010: every status the hosts show is a word and a symbol before it is a color, and is
/// spoken with its kind. Two statuses that share a color never share a word or a symbol.
@Suite struct AccessibilityVocabularyTests {
    /// Statuses of one kind must differ in word and in symbol, whatever their tones.
    private func expectDistinct(_ statuses: [StatusDescriptor], kind: String) {
        #expect(Set(statuses.map(\.title)).count == statuses.count, "\(kind): every status has its own word")
        #expect(Set(statuses.map(\.symbol)).count == statuses.count, "\(kind): every status has its own symbol")
        for status in statuses {
            #expect(status.kind == kind)
            #expect(status.spokenLabel == "\(kind): \(status.title)")
            #expect(!status.title.isEmpty && !status.symbol.isEmpty)
        }
    }

    @Test func lifecycleStatesAreWordsAndSymbols() {
        let states = ImplementationState.allCases.map(\.status)
        expectDistinct(states, kind: "State")
        // Device verified and release ready share green; only the word and symbol tell them apart.
        #expect(ImplementationState.deviceVerified.tone == ImplementationState.releaseReady.tone)
    }

    @Test func readinessValuesAreWordsAndSymbols() {
        expectDistinct(CapabilityReadiness.allCases.map(\.status), kind: "Readiness")
    }

    @Test func gateStatesHaveTheirOwnSymbols() {
        let symbols = GateState.allCases.map(\.symbolName)
        #expect(Set(symbols).count == symbols.count)
        // Denied and restricted share a tone, so they must not share a symbol.
        #expect(GateState.denied.tone == GateState.restricted.tone)
        #expect(GateState.denied.symbolName != GateState.restricted.symbolName)
    }

    @Test func toneIsOnlyAColor() {
        // Each tone maps to one semantic color; the mapping carries no words of its own.
        #expect(Set(StatusTone.allCases.map { "\($0.color)" }).count == StatusTone.allCases.count)
    }

    @Test @MainActor func receiptStatusesDifferInWordAndSymbol() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AccessibilityVocabularyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: LabStoreLocation.fileName)
        let library = LabLibrary(locateStore: { url })
        await library.start()
        let cobalt = try #require(library.collections.first?.items.dropFirst().first)
        let archive = try #require(await library.setArchived(cobalt, true))
        _ = try #require(await library.resetDemo())
        let conflict = try #require(await library.undo(archive))

        let committed = ReceiptPresentation(archive).statusDescriptor
        let refused = ReceiptPresentation(conflict).statusDescriptor
        #expect(committed.spokenLabel == "Status: Committed")
        #expect(refused.spokenLabel == "Status: Not applied: expected revision 2, found 3")
        #expect(committed.symbol != refused.symbol)
        #expect(committed.tone != refused.tone)
    }
}
