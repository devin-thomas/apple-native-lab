import ContextCards
import LabDomain
import Testing

@Suite struct ContextCardsQualificationTests {
    @Test func anArchiveWithoutACommitGrantCannotChangeTheSample() async throws {
        let backend = try await CardBackend.seeded()
        let amber = try await backend.actions(.appUI).read(CardSeed.amber)
        let request = OperationRequest(
            id: cardRequest(20).id,
            operation: .archiveItem(id: amber.id, expected: amber.revision),
            actor: CardBackend.appIntent
        )
        await #expect(throws: OperationError.self) {
            try await backend.service.perform(request)
        }
        #expect(try await backend.actions(.appUI).read(amber.id) == amber)
        #expect(await backend.store.receipt(for: request.id) == nil)
    }
}
