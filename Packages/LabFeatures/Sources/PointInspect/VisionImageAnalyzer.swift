import Foundation

#if canImport(Vision) && (os(iOS) || os(macOS))
import Vision
#endif

/// On-device OCR and barcode detection through Vision.
///
/// Both requests take the image bytes and return text. A barcode payload is copied into a
/// `BarcodeReading`, which cannot execute it. Watch and tvOS hosts do not link this module.
public struct VisionImageAnalyzer: ImageInspecting {
    public static var isCompiled: Bool {
        #if canImport(Vision) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    public init() {}

    public func inspect(_ image: SelectedImage) async throws(InspectFailure) -> OpticalReading {
        #if canImport(Vision) && (os(iOS) || os(macOS))
        if Task.isCancelled { throw .cancelled }
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let barcodeRequest = DetectBarcodesRequest()
        let text: [RecognizedTextObservation]
        let codes: [BarcodeObservation]
        do {
            text = try await textRequest.perform(on: image.data)
            if Task.isCancelled { throw CancellationError() }
            codes = try await barcodeRequest.perform(on: image.data)
        } catch is CancellationError {
            throw .cancelled
        } catch is InspectFailure {
            throw .cancelled
        } catch {
            throw .analysisFailed
        }
        if Task.isCancelled { throw .cancelled }
        let lines = text.map { RecognizedLine(text: $0.transcript, confidence: Double($0.confidence)) }
        let barcodes = codes.compactMap { code -> BarcodeReading? in
            guard let payload = code.payloadString else { return nil }
            return BarcodeReading(payload: payload, symbology: String(describing: code.symbology), confidence: Double(code.confidence))
        }
        return OpticalReading(lines: lines, barcodes: barcodes, engine: .vision)
        #else
        throw .analysisFailed
        #endif
    }
}
