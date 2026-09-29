import Foundation
import LabDomain
import Testing

@Suite struct IdentityTests {
    @Test func sameUUIDNamesDifferentEntitiesByKind() {
        let raw = uuid(7)
        let item = EntityReference.item(ItemID(rawValue: raw))
        let collection = EntityReference.collection(CollectionID(rawValue: raw))
        #expect(item != collection)
        #expect(item.rawID == collection.rawID)
        #expect(item.kind == .item && collection.kind == .collection)
    }

    @Test func identifiersEncodeAsBareUUIDs() throws {
        let id = ItemID(rawValue: uuid(1))
        let json = String(decoding: try JSONEncoder().encode(id), as: UTF8.self)
        #expect(json == "\"00000000-0000-0000-0000-000000000001\"")
        #expect(try JSONDecoder().decode(ItemID.self, from: Data(json.utf8)) == id)
        let request = RequestID(rawValue: uuid(2))
        #expect(try JSONDecoder().decode(RequestID.self, from: JSONEncoder().encode(request)) == request)
    }

    @Test func entityReferencesRoundTrip() throws {
        let reference = EntityReference.collection(CollectionID(rawValue: uuid(3)))
        let decoded = try JSONDecoder().decode(EntityReference.self, from: JSONEncoder().encode(reference))
        #expect(decoded == reference)
    }

    @Test func revisionsStartAtOneAndOnlyIncrease() throws {
        #expect(Revision.initial.rawValue == 1)
        #expect(Revision.initial.next() == .r(2))
        #expect(Revision.initial < Revision.initial.next())
        #expect(Revision(rawValue: 0) == nil)
        #expect(Revision(rawValue: -4) == nil)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Revision.self, from: Data("0".utf8)) }
        #expect(try JSONDecoder().decode(Revision.self, from: Data("3".utf8)) == .r(3))
    }

    @Test func identityIsNeverTheDisplayName() async throws {
        let lab = Harness()
        let samples = try await lab.makeCollection()
        let first = try await lab.makeItem("Amber sample", in: samples)
        let second = try await lab.makeItem("Amber sample", in: samples)
        #expect(first.id != second.id)

        try await lab.perform(.updateItem(id: first.id, expected: first.revision, changes: ItemChanges(title: "Cobalt sample")))
        let renamed = try await lab.item(first.id)
        #expect(renamed.id == first.id)
        #expect(renamed.title == "Cobalt sample")
        #expect(try await lab.item(second.id).title == "Amber sample")
    }
}

@Suite struct PayloadValidationTests {
    @Test func titlesAreTrimmedAndBounded() throws {
        #expect(try title("  Amber sample \n").value == "Amber sample")
        #expect(throws: ValidationError.emptyTitle) { try title("") }
        #expect(throws: ValidationError.emptyTitle) { try title(" \n\t ") }
        #expect(try title(String(repeating: "a", count: 120)).value.count == 120)
        #expect(throws: ValidationError.titleTooLong(limit: 120)) { try title(String(repeating: "a", count: 121)) }
    }

    @Test func titlesRejectControlCharactersAndLineBreaks() {
        #expect(throws: ValidationError.controlCharacter(in: .title)) { try title("Amber\nsample") }
        #expect(throws: ValidationError.controlCharacter(in: .title)) { try title("Amber\u{07}") }
    }

    @Test func notesAllowLineBreaksButNotOtherControls() throws {
        #expect(try note("First line\nSecond\tline").value == "First line\nSecond\tline")
        #expect(ItemNote.empty.value.isEmpty)
        #expect(throws: ValidationError.controlCharacter(in: .note)) { try note("bell\u{07}") }
        #expect(throws: ValidationError.noteTooLong(limit: 2_000)) { try note(String(repeating: "n", count: 2_001)) }
    }

    @Test func anUpdateMustChangeSomething() {
        #expect(throws: ValidationError.emptyChanges) { try ItemChanges() }
    }

    @Test func decodingRevalidatesThePayload() throws {
        let valid = DomainOperation.createCollection(draft: CollectionDraft(id: CollectionID(rawValue: uuid(1)), title: "Samples"))
        let json = String(decoding: try JSONEncoder().encode(valid), as: UTF8.self)
        #expect(try JSONDecoder().decode(DomainOperation.self, from: Data(json.utf8)) == valid)

        let blankTitle = json.replacingOccurrences(of: "\"Samples\"", with: "\"   \"")
        #expect(throws: ValidationError.emptyTitle) {
            try JSONDecoder().decode(DomainOperation.self, from: Data(blankTitle.utf8))
        }
        #expect(throws: ValidationError.emptyChanges) {
            try JSONDecoder().decode(ItemChanges.self, from: Data("{}".utf8))
        }
    }

    @Test func searchFiltersAreBounded() throws {
        #expect(throws: ValidationError.resultLimitOutOfRange(allowed: 1...200)) { try ItemFilter(limit: 0) }
        #expect(throws: ValidationError.resultLimitOutOfRange(allowed: 1...200)) { try ItemFilter(limit: 201) }
        #expect(throws: ValidationError.searchTextTooLong(limit: 120)) { try ItemFilter(text: String(repeating: "q", count: 121)) }
        #expect(throws: ValidationError.controlCharacter(in: .searchText)) { try ItemFilter(text: "a\u{00}b") }
        #expect(try ItemFilter(text: "   ").text == nil)
    }

    @Test func anUnsupportedSchemaVersionIsRefusedWithoutMutation() async throws {
        let lab = Harness()
        let request = OperationRequest(
            id: RequestID(),
            operation: .createCollection(draft: CollectionDraft(title: "Samples")),
            actor: .appUI,
            schemaVersion: 2
        )
        await #expect(throws: OperationError.invalidPayload(.unsupportedSchemaVersion(2))) {
            try await lab.service.perform(request)
        }
        #expect(await lab.appliedCommits == 0)
        #expect(try await lab.service.findReceipt(for: request.id, as: .appUI) == nil)
    }
}
