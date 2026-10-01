import Foundation
import Testing
@testable import DocumentsEverywhere

@Suite("Revision rules")
struct RevisionRulesTests {
    @Test("External content edit bumps content when the base matches")
    func externalContentEditBumpsContentWhenTheBaseMatches() {
        let current = DocumentRevision(content: 3, metadata: 2)
        let decision = RevisionRules.apply(current: current, base: current, change: .content)
        #expect(decision == .accepted(DocumentRevision(content: 4, metadata: 2)))
    }

    @Test("External metadata edit bumps metadata only")
    func externalMetadataEditBumpsMetadataOnly() {
        let current = DocumentRevision.initial
        let decision = RevisionRules.apply(current: current, base: current, change: .metadata)
        #expect(decision == .accepted(DocumentRevision(content: 1, metadata: 2)))
    }

    @Test("Stale base never overwrites")
    func staleBaseNeverOverwrites() {
        let current = DocumentRevision(content: 5, metadata: 1)
        let stale = DocumentRevision(content: 4, metadata: 1)
        let decision = RevisionRules.apply(current: current, base: stale, change: .content)
        #expect(decision == .conflict(expected: stale, found: current))
    }

    @Test("Revision round-trips through File Provider version bytes")
    func revisionRoundTripsThroughVersionBytes() {
        let revision = DocumentRevision(content: 42, metadata: 7)
        let restored = DocumentRevision.from(
            contentVersion: revision.contentVersionData,
            metadataVersion: revision.metadataVersionData
        )
        #expect(restored == revision)
    }
}
