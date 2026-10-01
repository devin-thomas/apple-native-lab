import Foundation

/// Why a pass payload, barcode, update, or signing request was refused. Every case is content-free
/// of secrets: it never echoes a private key, certificate, or barcode message into `userMessage`.
public enum WalletMomentError: Error, Hashable, Sendable {
    case emptyField(PassField)
    case fieldTooLong(PassField, limit: Int)
    case controlCharacter(PassField)
    case invalidDateOrder
    case emptyBarcodeMessage
    case barcodeMessageTooLong(limit: Int)
    case barcodeAltTextTooLong(limit: Int)
    /// The payload names a field that claims signing material or authority. Passes are data until
    /// an operator signs them outside the client; keys never enter this module.
    case authorityOrSigningField(String)
    case nothingToUpdate
    case updateTagUnchanged
    case cancelled
    case notAuthorized
    case storeUnavailable
    case unavailable
    /// No operator-supplied signing environment is configured, so no signed pass was produced.
    case signingUnavailable
    /// The operator tool refused or failed without returning pass bytes.
    case signingFailed
    case noDestination
    case destinationUnavailable
    case identifierConflict
    case stateChanged
}

public enum PassField: String, Hashable, Sendable, CaseIterable {
    case serialNumber
    case organizationName
    case eventName
    case venue
    case seat
    case updateTag
    case barcodeMessage
    case barcodeAltText
}

extension WalletMomentError: LocalizedError, CustomStringConvertible {
    public var userMessage: String {
        switch self {
        case .emptyField(let field):
            "This pass has no \(field.displayName). Nothing was changed."
        case .fieldTooLong(let field, let limit):
            "This pass’s \(field.displayName) is longer than \(limit) characters. Nothing was changed."
        case .controlCharacter(let field):
            "This pass’s \(field.displayName) has characters that can’t be stored. Nothing was changed."
        case .invalidDateOrder:
            "This pass’s expiration is not after its start. Nothing was changed."
        case .emptyBarcodeMessage:
            "This pass’s barcode message is empty. The barcode is display data only and was refused. Nothing was changed."
        case .barcodeMessageTooLong(let limit):
            "This pass’s barcode message is longer than \(limit) characters. Nothing was changed."
        case .barcodeAltTextTooLong(let limit):
            "This pass’s barcode label is longer than \(limit) characters. Nothing was changed."
        case .authorityOrSigningField:
            "This pass carries a field that claims a signing key, certificate, or authorization. Keys stay outside the client, so it was refused. Nothing was changed."
        case .nothingToUpdate:
            "That update names no field to change. Nothing was changed."
        case .updateTagUnchanged:
            "That update reuses the pass’s current update tag. Nothing was changed."
        case .cancelled:
            "The change was cancelled. Nothing was changed."
        case .notAuthorized:
            "This change isn’t allowed from here. Nothing was changed."
        case .storeUnavailable:
            "The lab store couldn’t be used, so nothing was changed. Try again."
        case .unavailable:
            "The lab store isn’t open yet. Try again in a moment. Nothing was changed."
        case .signingUnavailable:
            "No operator-supplied signing environment is configured. The unsigned preview still works. Nothing was signed."
        case .signingFailed:
            "The operator signing tool did not produce a pass. Nothing was signed."
        case .noDestination:
            "Choose a collection for the event card. Nothing was changed."
        case .destinationUnavailable:
            "The chosen collection can’t take new items. Nothing was changed."
        case .identifierConflict:
            "This request conflicts with an earlier one. Review the pass again. Nothing was changed."
        case .stateChanged:
            "The lab changed while you were reviewing this pass. Review it again. Nothing was changed."
        }
    }

    public var errorDescription: String? { userMessage }

    public var code: String {
        switch self {
        case .emptyField(let field): "empty-field/\(field.rawValue)"
        case .fieldTooLong(let field, _): "field-too-long/\(field.rawValue)"
        case .controlCharacter(let field): "control-character/\(field.rawValue)"
        case .invalidDateOrder: "invalid-date-order"
        case .emptyBarcodeMessage: "empty-barcode-message"
        case .barcodeMessageTooLong: "barcode-message-too-long"
        case .barcodeAltTextTooLong: "barcode-alt-text-too-long"
        case .authorityOrSigningField(let name): "authority-or-signing-field/\(name.lowercased())"
        case .nothingToUpdate: "nothing-to-update"
        case .updateTagUnchanged: "update-tag-unchanged"
        case .cancelled: "cancelled"
        case .notAuthorized: "not-authorized"
        case .storeUnavailable: "store-unavailable"
        case .unavailable: "unavailable"
        case .signingUnavailable: "signing-unavailable"
        case .signingFailed: "signing-failed"
        case .noDestination: "no-destination"
        case .destinationUnavailable: "destination-unavailable"
        case .identifierConflict: "identifier-conflict"
        case .stateChanged: "state-changed"
        }
    }

    public var description: String { code }
}

extension PassField {
    var displayName: String {
        switch self {
        case .serialNumber: "serial number"
        case .organizationName: "organization name"
        case .eventName: "event name"
        case .venue: "venue"
        case .seat: "seat"
        case .updateTag: "update tag"
        case .barcodeMessage: "barcode message"
        case .barcodeAltText: "barcode label"
        }
    }
}
