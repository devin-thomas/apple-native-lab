import Foundation

/// The bundled sample event pass: an original fictional Harbor Lantern Festival ticket. No real
/// venue, account, or signing material.
public enum SampleEvent {
    /// Stable IDs so tests and the UI talk about the same fixture.
    public static let passID = UUID(uuidString: "A38E0001-0000-4000-8000-000000000038")!
    public static let serialNumber = "HLF-2026-0042"

    /// Absolute times used by the fixture and by tests that freeze the clock.
    public static let startsAt = date("2026-10-17T18:00:00Z")
    public static let expiresAt = date("2026-10-18T02:00:00Z")
    /// A mid-event instant while the pass is active.
    public static let duringEvent = date("2026-10-17T20:30:00Z")
    /// After expiration.
    public static let afterExpiry = date("2026-10-18T03:00:00Z")
    /// Before the event.
    public static let beforeEvent = date("2026-10-17T12:00:00Z")

    public static let definition = PassDefinition(
        id: passID,
        serialNumber: serialNumber,
        organizationName: "Harbor Lantern Collective",
        eventName: "Harbor Lantern Festival",
        venue: "North Pier Pavilion",
        seat: "GA-42",
        startsAt: startsAt,
        expiresAt: expiresAt,
        barcode: PassBarcode(
            format: .qr,
            message: "HLF2026:GA42:A38E0001",
            altText: "Ticket HLF-2026-0042"
        ),
        updateTag: "v1"
    )

    /// A seat reassignment update that keeps the same event window.
    public static let seatUpdate = PassUpdate(
        updateTag: "v2-seat",
        seat: "GA-17",
        barcode: PassBarcode(
            format: .qr,
            message: "HLF2026:GA17:A38E0001",
            altText: "Ticket HLF-2026-0042 seat GA-17"
        )
    )

    /// An update that expires the pass immediately relative to `duringEvent`.
    public static let expireUpdate = PassUpdate(
        updateTag: "v2-expired",
        expiresAt: date("2026-10-17T19:00:00Z")
    )

    public static func preview(at now: Date = duringEvent) -> PassPreview {
        PassPreview(definition: definition, at: now)
    }

    /// Loads and checks the on-disk fixture against the compiled sample. Throws when they disagree
    /// or when the fixture smuggles a forbidden field.
    public static func loadFixture(from url: URL) throws -> PassDefinition {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw WalletMomentError.stateChanged
        }
        try PassValidator.refuseAuthorityFields(in: root)
        if let nested = root["pass"] as? [String: Any] {
            try PassValidator.refuseAuthorityFields(in: nested)
            if let barcode = nested["barcode"] as? [String: Any] {
                try PassValidator.refuseAuthorityFields(in: barcode)
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct File: Decodable {
            let format: String
            let formatVersion: Int
            let pass: PassDefinition
        }
        let file = try decoder.decode(File.self, from: data)
        guard file.format == "native-lab-event-pass", file.formatVersion == 1 else {
            throw WalletMomentError.stateChanged
        }
        return try PassValidator.validate(file.pass)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
