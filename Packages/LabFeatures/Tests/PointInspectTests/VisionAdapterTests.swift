import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import Testing
@testable import PointInspect

/// Vision on images this test draws. A pass is an adapter result on this Mac, not a camera
/// and not a physical device.
@Suite struct VisionAdapterTests {
    @Test func recognizedTextComesBackAsLines() async throws {
        try #require(VisionImageAnalyzer.isCompiled)
        let data = try drawn("SWATCH CARD")
        let image = try SelectedImage(data: data, origin: .userSelected)
        let reading = try await VisionImageAnalyzer().inspect(image)
        #expect(reading.engine == .vision)
        let text = reading.lines.map(\.text).joined(separator: " ")
        #expect(text.localizedStandardContains("SWATCH"))
        #expect(reading.barcodes.allSatisfy { !$0.canExecute })
    }

    @Test func aBarcodePayloadIsText() async throws {
        try #require(VisionImageAnalyzer.isCompiled)
        let payload = "LAB012-DO-NOT-RUN"
        let data = try qrCode(payload)
        let image = try SelectedImage(data: data, origin: .userSelected)
        let reading = try await VisionImageAnalyzer().inspect(image)
        #expect(reading.barcodes.contains { $0.payload == payload && !$0.canExecute })
    }
}

private func drawn(_ text: String) throws -> Data {
    let width = 800
    let height = 240
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw DrawError() }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
    let attributed = CFAttributedStringCreateMutable(nil, 0)!
    CFAttributedStringReplaceString(attributed, CFRange(location: 0, length: 0), text as CFString)
    let range = CFRange(location: 0, length: text.utf16.count)
    CFAttributedStringSetAttribute(attributed, range, kCTFontAttributeName, font)
    CFAttributedStringSetAttribute(attributed, range, kCTForegroundColorAttributeName, CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 40, y: 80)
    CTLineDraw(line, context)
    guard let cgImage = context.makeImage() else { throw DrawError() }
    return try pngData(cgImage)
}

private func qrCode(_ payload: String) throws -> Data {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw DrawError() }
    filter.setValue(Data(payload.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { throw DrawError() }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    let context = CIContext()
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { throw DrawError() }
    return try pngData(cgImage)
}

private func pngData(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
        throw DrawError()
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawError() }
    return data as Data
}

private struct DrawError: Error {}
