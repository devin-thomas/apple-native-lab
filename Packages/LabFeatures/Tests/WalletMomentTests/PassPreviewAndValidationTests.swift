import Foundation
import Testing
@testable import WalletMoment

@Suite struct PassPreviewAndValidationTests {
    @Test func sampleFixtureMatchesCompiledDefinition() throws {
        let loaded = try SampleEvent.loadFixture(from: Fixtures.samplePass)
        #expect(loaded == SampleEvent.definition)
        #expect(try PassValidator.validate(loaded) == loaded)
    }

    @Test func unsignedPreviewNeverClaimsASignature() {
        let preview = SampleEvent.preview()
        #expect(!preview.isSigned)
        #expect(preview.lifecycle == .active)
        #expect(preview.headline == "Harbor Lantern Festival")
        #expect(preview.signingNote.contains("Unsigned"))
        #expect(!preview.signingNote.lowercased().contains("private key"))
    }

    @Test func lifecycleIsHonestAtEachClockPoint() {
        #expect(PassLifecycle.state(of: SampleEvent.definition, at: SampleEvent.beforeEvent) == .upcoming)
        #expect(PassLifecycle.state(of: SampleEvent.definition, at: SampleEvent.duringEvent) == .active)
        #expect(PassLifecycle.state(of: SampleEvent.definition, at: SampleEvent.afterExpiry) == .expired)
        #expect(PassLifecycle.state(of: SampleEvent.definition, at: SampleEvent.expiresAt) == .expired)
        #expect(PassPreview(definition: SampleEvent.definition, at: SampleEvent.afterExpiry).lifecycle.sentence
                == "This pass has expired.")
    }

    @Test func applyingASeatUpdateChangesTheBarcodeDisplayOnly() throws {
        let next = SampleEvent.definition.applying(SampleEvent.seatUpdate)
        #expect(next.seat == "GA-17")
        #expect(next.updateTag == "v2-seat")
        #expect(next.barcode.message == "HLF2026:GA17:A38E0001")
        #expect(try PassValidator.validate(SampleEvent.seatUpdate, against: SampleEvent.definition) == SampleEvent.seatUpdate)
        // The barcode remains display data: validation success is not authorization.
        #expect(next.barcode.message != SampleEvent.definition.barcode.message)
    }

    @Test func expireUpdateMakesThePassExpiredDuringTheEvent() {
        let next = SampleEvent.definition.applying(SampleEvent.expireUpdate)
        #expect(PassLifecycle.state(of: next, at: SampleEvent.duringEvent) == .expired)
    }

    @Test func invalidPayloadIsRefused() {
        #expect(throws: WalletMomentError.emptyField(.eventName)) {
            try PassValidator.validate(PassDefinition(
                serialNumber: "X", organizationName: "O", eventName: "  ", venue: "V", seat: "S",
                startsAt: SampleEvent.startsAt, expiresAt: SampleEvent.expiresAt,
                barcode: SampleEvent.definition.barcode, updateTag: "v1"
            ))
        }
        #expect(throws: WalletMomentError.invalidDateOrder) {
            try PassValidator.validate(PassDefinition(
                serialNumber: "X", organizationName: "O", eventName: "E", venue: "V", seat: "S",
                startsAt: SampleEvent.expiresAt, expiresAt: SampleEvent.startsAt,
                barcode: SampleEvent.definition.barcode, updateTag: "v1"
            ))
        }
        #expect(throws: WalletMomentError.emptyBarcodeMessage) {
            try PassValidator.validate(PassBarcode(format: .qr, message: "  ", altText: "label"))
        }
        #expect(throws: WalletMomentError.nothingToUpdate) {
            try PassValidator.validate(PassUpdate(updateTag: "v2"), against: SampleEvent.definition)
        }
        #expect(throws: WalletMomentError.updateTagUnchanged) {
            try PassValidator.validate(
                PassUpdate(updateTag: SampleEvent.definition.updateTag, seat: "Z"),
                against: SampleEvent.definition
            )
        }
    }

    @Test func hostileSigningKeyFixtureIsRefused() throws {
        let data = try Data(contentsOf: Fixtures.hostileKey)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(throws: WalletMomentError.self) {
            try PassValidator.refuseAuthorityFields(in: object)
        }
        // loadFixture also refuses before decoding the pass body when a top-level key is forbidden.
        #expect(throws: WalletMomentError.self) {
            try SampleEvent.loadFixture(from: Fixtures.hostileKey)
        }
    }

    @Test func barcodeIsNeverAnAuthorizationSurface() {
        // There is no API that turns a barcode into a grant, scope, or adapter. The extras JSON
        // stores the message as data; EventCardOperations documents that reading it issues no grant.
        let barcode = SampleEvent.definition.barcode
        #expect(barcode.message == "HLF2026:GA42:A38E0001")
        #expect(PassValidator.forbiddenFieldNames.contains("grant"))
        #expect(PassValidator.forbiddenFieldNames.contains("authorization"))
        #expect(!PassValidator.forbiddenFieldNames.contains(barcode.message))
    }
    @Test func whitespaceCannotHideControlCharactersOrOversizedPayloads() {
        #expect(throws: WalletMomentError.controlCharacter(.barcodeMessage)) {
            try PassValidator.validate(PassBarcode(format: .qr, message: "\nTICKET\n", altText: "Ticket"))
        }
        #expect(throws: WalletMomentError.barcodeMessageTooLong(limit: PassLimits.barcodeMessage)) {
            try PassValidator.validate(PassBarcode(format: .qr, message: String(repeating: " ", count: 201) + "X", altText: "Ticket"))
        }
    }

}
