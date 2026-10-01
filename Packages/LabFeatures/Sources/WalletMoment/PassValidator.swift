import Foundation

/// Validates a pass definition or update. Validation never authorizes a domain operation: a
/// barcode that passes these checks is still only display data.
public enum PassValidator {
    /// Top-level JSON names that claim signing material or domain authority. Compared without
    /// regard to case. A fixture or import that carries one is refused rather than previewed.
    public static let forbiddenFieldNames: Set<String> = [
        "privatekey", "private_key", "passcertificate", "pass_certificate", "wwdrcertificate",
        "wwdr_certificate", "signingkey", "signing_key", "signingidentity", "certificate",
        "cert", "pem", "p12", "pkcs12", "passphrase", "password", "authenticationtoken",
        "authorization", "grant", "grants", "actor", "adapter", "operation", "operations",
        "permission", "permissions", "scope", "scopes", "bookmark", "bookmarkdata",
    ]

    /// Validates `definition` and returns it unchanged, or throws.
    @discardableResult
    public static func validate(_ definition: PassDefinition) throws(WalletMomentError) -> PassDefinition {
        try requireText(definition.serialNumber, field: .serialNumber, limit: PassLimits.serialNumber)
        try requireText(definition.organizationName, field: .organizationName, limit: PassLimits.organizationName)
        try requireText(definition.eventName, field: .eventName, limit: PassLimits.eventName)
        try requireText(definition.venue, field: .venue, limit: PassLimits.venue)
        try requireText(definition.seat, field: .seat, limit: PassLimits.seat)
        try requireText(definition.updateTag, field: .updateTag, limit: PassLimits.updateTag)
        try validate(definition.barcode)
        guard definition.startsAt.timeIntervalSince1970.isFinite,
              definition.expiresAt.timeIntervalSince1970.isFinite,
              definition.expiresAt > definition.startsAt else { throw .invalidDateOrder }
        return definition
    }

    /// Validates an update against the current definition. The update tag must change.
    @discardableResult
    public static func validate(_ update: PassUpdate, against current: PassDefinition) throws(WalletMomentError) -> PassUpdate {
        _ = try validate(current)
        try requireText(update.updateTag, field: .updateTag, limit: PassLimits.updateTag)
        guard update.changesAnything else { throw .nothingToUpdate }
        guard update.updateTag != current.updateTag else { throw .updateTagUnchanged }
        if let venue = update.venue { try requireText(venue, field: .venue, limit: PassLimits.venue) }
        if let seat = update.seat { try requireText(seat, field: .seat, limit: PassLimits.seat) }
        if let barcode = update.barcode { try validate(barcode) }
        if let expiresAt = update.expiresAt {
            guard expiresAt.timeIntervalSince1970.isFinite, expiresAt > current.startsAt else { throw .invalidDateOrder }
        }
        return update
    }

    public static func validate(_ barcode: PassBarcode) throws(WalletMomentError) {
        let message = barcode.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw .emptyBarcodeMessage }
        guard barcode.message.count <= PassLimits.barcodeMessage else {
            throw .barcodeMessageTooLong(limit: PassLimits.barcodeMessage)
        }
        guard !barcode.message.containsControlCharacter(except: []) else {
            throw .controlCharacter(.barcodeMessage)
        }
        let alt = barcode.altText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alt.isEmpty else { throw .emptyField(.barcodeAltText) }
        guard barcode.altText.count <= PassLimits.barcodeAltText else {
            throw .barcodeAltTextTooLong(limit: PassLimits.barcodeAltText)
        }
        guard !barcode.altText.containsControlCharacter(except: []) else {
            throw .controlCharacter(.barcodeAltText)
        }
    }

    /// Refuses a JSON object whose keys claim signing material or domain authority. Used when
    /// decoding fixtures so a hostile file cannot smuggle a key into the client.
    public static func refuseAuthorityFields(in object: [String: Any]) throws(WalletMomentError) {
        for key in object.keys {
            let normalized = key.lowercased().filter { $0.isLetter || $0 == "_" }
            if forbiddenFieldNames.contains(normalized) || forbiddenFieldNames.contains(key.lowercased()) {
                throw .authorityOrSigningField(key)
            }
        }
    }

    private static func requireText(_ raw: String, field: PassField, limit: Int) throws(WalletMomentError) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyField(field) }
        guard raw.count <= limit else { throw .fieldTooLong(field, limit: limit) }
        guard !raw.containsForbiddenControl else { throw .controlCharacter(field) }
    }
}

private extension String {
    /// True when the string holds a C0/C1 control scalar. Pass fields are single-line.
    var containsForbiddenControl: Bool {
        unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    func containsControlCharacter(except allowed: [Character]) -> Bool {
        contains { character in
            if allowed.contains(character) { return false }
            return character.unicodeScalars.contains { $0.properties.generalCategory == .control }
        }
    }
}
