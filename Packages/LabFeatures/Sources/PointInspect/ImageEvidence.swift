import CryptoKit
import Foundation
import LabDomain

/// Why an image or a read was refused before it became a record.
public enum InspectFailure: Error, Hashable, Sendable {
    case emptyImage
    case imageTooLarge(bytes: Int)
    case unsupportedImage
    case cancelled
    case timedOut
    case analysisFailed
    case modelUnavailable(ImageModelGate)
    case modelFailed
    case invalidText(String)
    case refused(OperationError)
    case unavailable(String)

    public var message: String {
        switch self {
        case .emptyImage: "Choose an image first."
        case .imageTooLarge: "That image is larger than \(InspectLimits.imageBytes / (1024 * 1024)) MB."
        case .unsupportedImage: "Use a PNG, JPEG, or GIF."
        case .cancelled: "The read was cancelled. Nothing was saved."
        case .timedOut: "The read took too long and was stopped. Nothing was saved."
        case .analysisFailed: "The image could not be read. You can still type the record."
        case .modelUnavailable(let gate): gate.message
        case .modelFailed: "The on-device model did not return a description. You can use the recognized text or type the record."
        case .invalidText(let reason): reason
        case .refused(let error): error.inspectSentence
        case .unavailable(let reason): reason
        }
    }
}

/// Why the on-device image description cannot run. Read from the model, never from the device name.
public enum ImageModelGate: Hashable, Sendable {
    case notCompiled
    case imageInputUnavailable
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case localeNotSupported
    case unrecognized

    public var message: String {
        switch self {
        case .notCompiled: "This platform has no on-device model path. OCR and the manual fields still work."
        case .imageInputUnavailable: "This system cannot attach an image to the on-device model. OCR and the manual fields still work."
        case .deviceNotEligible: "This device cannot run the on-device model. OCR and the manual fields still work."
        case .appleIntelligenceNotEnabled: "Apple Intelligence is turned off. OCR and the manual fields still work."
        case .modelNotReady: "The on-device model is not ready. OCR and the manual fields still work."
        case .localeNotSupported: "The on-device model does not support this language. OCR and the manual fields still work."
        case .unrecognized: "The on-device model is unavailable. OCR and the manual fields still work."
        }
    }
}

/// Where the bytes came from. A fixture replay is not a camera capture.
public enum ImageOrigin: Hashable, Sendable {
    case userSelected
    case fixtureReplay
    /// System visual-search labels. This app did not keep the system's pixels.
    case systemVisualSearch

    public var label: String {
        switch self {
        case .userSelected: "Image you chose"
        case .fixtureReplay: "Fixture replay"
        case .systemVisualSearch: "System visual search"
        }
    }
}

public enum ImageMedia: String, Hashable, Sendable {
    case png
    case jpeg
    case gif
}

/// Proof of which image a record describes. The record stores the digest, not a copy of the file,
/// and the default is that nothing leaves the device.
public struct ImageEvidence: Hashable, Sendable {
    public let digest: String
    public let byteCount: Int
    /// Nil when this app stored no image bytes, as with system-search labels.
    public let media: ImageMedia?
    public let origin: ImageOrigin
    /// This build has no network route for an image. The value is fixed.
    public var staysLocal: Bool { true }

    public var digestPrefix: String { String(digest.prefix(12)) }
}

/// What the person allowed. Entering the experiment grants none of this.
///
/// Camera capture is not offered. This build does not recognize identity. System visual search
/// stays off until the person turns it on, and turning it on still does not upload the photo:
/// `staysLocal` remains true either way, which is what "local by default" requires of the off state.
public struct CaptureConsent: Hashable, Sendable {
    public var cameraUsed: Bool
    public var visualSearch: VisualSearchChoice
    public var recognizesIdentity: Bool { false }

    public static let chosenImage = CaptureConsent(cameraUsed: false, visualSearch: .off)
    public static let fixtureReplay = CaptureConsent(cameraUsed: false, visualSearch: .off)

    public init(cameraUsed: Bool, visualSearch: VisualSearchChoice) {
        self.cameraUsed = cameraUsed
        self.visualSearch = visualSearch
    }

    /// Photos and their text stay on device. There is no setting in this build that sends them out.
    public var staysLocal: Bool { true }
}

/// Whether this inspection participates in the system's visual search. Off unless the person asks.
public enum VisualSearchChoice: String, Hashable, Sendable {
    case off
    /// The system query. This app still does not upload the image.
    case systemQuery

    public var label: String {
        switch self {
        case .off: "Off"
        case .systemQuery: "On, on this device"
        }
    }
}

/// Bytes a person chose, or the bundled fixture, checked before any analyzer sees them.
public struct SelectedImage: Hashable, Sendable {
    public let data: Data
    public let evidence: ImageEvidence

    public init(data: Data, origin: ImageOrigin) throws(InspectFailure) {
        guard !data.isEmpty else { throw .emptyImage }
        guard data.count <= InspectLimits.imageBytes else { throw .imageTooLarge(bytes: data.count) }
        guard let media = Self.media(of: data) else { throw .unsupportedImage }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.data = data
        evidence = ImageEvidence(digest: digest, byteCount: data.count, media: media, origin: origin)
    }

    private static func media(of data: Data) -> ImageMedia? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) { return .gif }
        return nil
    }
}

extension OperationError {
    var inspectSentence: String {
        switch self {
        case .notFound: "The Inspections collection is not there yet."
        case .unauthorized: "That change is not allowed from here."
        case .ruleViolation(.alreadyExists(_)): "That record already exists."
        case .invalidPayload: "The record's text is not valid."
        default: "The lab did not accept this record."
        }
    }
}
