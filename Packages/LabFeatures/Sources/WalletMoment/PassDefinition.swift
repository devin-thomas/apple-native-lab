import Foundation

/// A lab-owned event pass definition. Not an Apple `PKPass`: it is the unsigned payload the
/// preview, validator, and update story operate on before any operator signing.
public struct PassDefinition: Hashable, Sendable, Codable {
    public let id: UUID
    public let serialNumber: String
    public let organizationName: String
    public let eventName: String
    public let venue: String
    public let seat: String
    /// When the event begins (UTC).
    public let startsAt: Date
    /// When the pass stops being valid (UTC). After this instant the lifecycle is `.expired`.
    public let expiresAt: Date
    public let barcode: PassBarcode
    /// Opaque revision tag for updates. Bumped when an update is applied.
    public let updateTag: String

    public init(
        id: UUID = UUID(),
        serialNumber: String,
        organizationName: String,
        eventName: String,
        venue: String,
        seat: String,
        startsAt: Date,
        expiresAt: Date,
        barcode: PassBarcode,
        updateTag: String
    ) {
        self.id = id
        self.serialNumber = serialNumber
        self.organizationName = organizationName
        self.eventName = eventName
        self.venue = venue
        self.seat = seat
        self.startsAt = startsAt
        self.expiresAt = expiresAt
        self.barcode = barcode
        self.updateTag = updateTag
    }

    /// A new definition with `update` applied. The update's own tag becomes the next `updateTag`.
    public func applying(_ update: PassUpdate) -> PassDefinition {
        PassDefinition(
            id: id,
            serialNumber: serialNumber,
            organizationName: organizationName,
            eventName: eventName,
            venue: update.venue ?? venue,
            seat: update.seat ?? seat,
            startsAt: startsAt,
            expiresAt: update.expiresAt ?? expiresAt,
            barcode: update.barcode ?? barcode,
            updateTag: update.updateTag
        )
    }
}

/// A change to an already-known pass. The barcode message may change for a reissue, but it still
/// never authorizes anything on its own.
public struct PassUpdate: Hashable, Sendable, Codable {
    public let updateTag: String
    public let venue: String?
    public let seat: String?
    public let expiresAt: Date?
    public let barcode: PassBarcode?

    public init(
        updateTag: String,
        venue: String? = nil,
        seat: String? = nil,
        expiresAt: Date? = nil,
        barcode: PassBarcode? = nil
    ) {
        self.updateTag = updateTag
        self.venue = venue
        self.seat = seat
        self.expiresAt = expiresAt
        self.barcode = barcode
    }

    public var changesAnything: Bool {
        venue != nil || seat != nil || expiresAt != nil || barcode != nil
    }
}

/// Barcode payload carried on a pass for display and scan-out. It is never a grant, scope, or
/// adapter credential (ADR-011): validating or showing it does not authorize a domain operation.
public struct PassBarcode: Hashable, Sendable, Codable {
    public enum Format: String, Hashable, Sendable, Codable, CaseIterable {
        case qr
        case pdf417
        case aztec
        case code128
    }

    public let format: Format
    public let message: String
    public let altText: String

    public init(format: Format, message: String, altText: String) {
        self.format = format
        self.message = message
        self.altText = altText
    }
}
