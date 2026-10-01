import Foundation

/// LAB-038 Wallet Moment: an original event pass with a useful update story and an explicit
/// signing boundary.
///
/// The module owns the pass definition, barcode validation, expiration state, unsigned preview,
/// and the operator-supplied signing seam. It never holds a pass-signing key, never treats a
/// barcode as authorization, and never opens the store. Hosts commit event cards through
/// `WalletMomentBackend` as the app UI, the same grant and receipt path as every other change.
public enum WalletMoment {
    public static let experimentID = "LAB-038"
    public static let title = "Wallet Moment"
    public static let symbol = "wallet.pass"

    /// The extras key under which a saved event card records its experiment ownership.
    public static let extrasExperimentKey = "experiment"
    public static let extrasKindKey = "kind"
    public static let extrasKindValue = "event-pass"

    static let diagnosticSubject = "LAB-038"
}

/// Bounds on a lab-owned pass definition. They are tighter than PassKit's documented limits where
/// that keeps fixtures and previews readable.
public enum PassLimits {
    public static let eventName = 80
    public static let venue = 80
    public static let seat = 40
    public static let serialNumber = 64
    public static let barcodeMessage = 200
    public static let barcodeAltText = 80
    public static let updateTag = 64
    public static let organizationName = 80
}
