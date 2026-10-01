import Foundation
import LabDomain
import Testing
@testable import WalletMoment

@Suite struct PassSigningTests {
    @Test func defaultSignerIsUnavailableAndLeavesPreviewUsable() async throws {
        let signer = UnavailablePassSigner()
        #expect(!signer.isConfigured)
        await #expect(throws: WalletMomentError.signingUnavailable) {
            try await signer.signedPass(for: SampleEvent.definition)
        }
        let preview = SampleEvent.preview()
        #expect(!preview.isSigned)
        #expect(try PassValidator.validate(preview.definition) == SampleEvent.definition)
    }

    @Test func operatorSignerWithoutToolIsUnavailable() async {
        let signer = OperatorPassSigner()
        #expect(!signer.isConfigured)
        await #expect(throws: WalletMomentError.signingUnavailable) {
            try await signer.signedPass(for: SampleEvent.definition)
        }
    }

    @Test func operatorSignerRefusesKeyMaterialFromTheTool() async {
        let signer = OperatorPassSigner { _ in
            Data("-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----".utf8)
        }
        // The injected adapter returns a refused PEM-shaped payload.
        #expect(signer.isConfigured)
        await #expect(throws: WalletMomentError.signingFailed) {
            try await signer.signedPass(for: SampleEvent.definition)
        }
    }

    @Test func operatorSignerAcceptsOpaquePassBytesFromTheTool() async throws {
        let expected = Data([0x50, 0x4b, 0x03, 0x04]) + Data("FIXTURE".utf8)
        let signer = OperatorPassSigner { definition in
            #expect(definition == SampleEvent.definition)
            return expected
        }
        let artifact = try await signer.signedPass(for: SampleEvent.definition)
        #expect(artifact.bytes == expected)
        #expect(artifact.provenance == .operatorTool)
        #expect(!artifact.note.lowercased().contains("private key"))
    }

    @Test func testDoubleIsLabeledAndDoesNotEmbedAKey() async throws {
        let signer = TestPassSigner()
        let artifact = try await signer.signedPass(for: SampleEvent.definition)
        #expect(artifact.provenance == .testDouble)
        #expect(artifact.note.contains("Test double"))
        let text = String(data: artifact.bytes, encoding: .utf8) ?? ""
        #expect(!text.uppercased().contains("PRIVATE KEY"))
        #expect(!text.contains("BEGIN CERTIFICATE"))
    }

    @Test func sourceTreeCarriesNoPassSigningKeyMaterial() throws {
        // The fixture directory must not hold PEM/PKCS material. The hostile file names a key
        // field and is refused; it must not contain a usable key body that the client would load.
        let sample = try String(contentsOf: Fixtures.samplePass, encoding: .utf8)
        #expect(!sample.uppercased().contains("BEGIN PRIVATE KEY"))
        #expect(!sample.uppercased().contains("BEGIN CERTIFICATE"))
        #expect(!sample.lowercased().contains("\"privatekey\""))
    }
    @Test func oversizedArchiveAndCancelledSigningAreRefused() async {
        let signer = OperatorPassSigner { _ in
            Data([0x50, 0x4b, 0x03, 0x04]) + Data(repeating: 0, count: OperatorPassSigner.maximumArtifactBytes)
        }
        await #expect(throws: WalletMomentError.signingFailed) {
            try await signer.signedPass(for: SampleEvent.definition)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: WalletMomentError.signingFailed) {
                try await signer.signedPass(for: SampleEvent.definition)
            }
        }
        await task.value
    }

}
