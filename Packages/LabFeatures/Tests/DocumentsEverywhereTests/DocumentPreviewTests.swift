import Foundation
import Testing
@testable import DocumentsEverywhere

@Suite("Document preview")
struct DocumentPreviewTests {
    @Test("Bundled samples preview without the File Provider")
    func bundledSamplesPreviewWithoutTheProvider() throws {
        let catalog = SampleCatalog.bundled
        #expect(catalog.samples.count == 2)
        for sample in catalog.samples {
            let preview = try DocumentPreviewBuilder.preview(sample: sample.id, from: catalog)
            #expect(!preview.title.isEmpty)
            #expect(preview.plainText.contains("Native Lab object"))
            #expect(preview.html.contains("<h1>"))
            #expect(preview.documentID != nil)
            #expect(preview.revision?.content == 1)
        }
    }

    @Test("Quick Look preview needs no provider connection")
    func quickLookPreviewNeedsNoProviderConnection() throws {
        let session = ProviderSession()
        #expect(session.state == .disabled)
        let preview = try DocumentPreviewBuilder.preview(sample: ProviderItemID(rawValue: "sample.harbor-note"))
        #expect(preview.title == "Harbor note")
        #expect(session.mirror.isEmpty)
    }

    @Test("Invalid input is refused")
    func invalidInputIsRefused() throws {
        let text = try Fixture.data("not-an-object.txt")
        #expect(throws: DocumentsEverywhereError.notALabObject) {
            try DocumentPreviewBuilder.preview(of: text)
        }
        let newer = try Fixture.data("newer-schema.anlab")
        #expect(throws: DocumentsEverywhereError.newerSchema(found: 99, supported: 1)) {
            try DocumentPreviewBuilder.preview(of: newer)
        }
    }

    @Test("Unknown sample is refused")
    func unknownSampleIsRefused() {
        #expect(throws: DocumentsEverywhereError.unknownSample) {
            try DocumentPreviewBuilder.preview(sample: ProviderItemID(rawValue: "sample.missing"))
        }
    }
}
