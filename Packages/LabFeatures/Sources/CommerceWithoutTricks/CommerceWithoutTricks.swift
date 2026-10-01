import LabDomain

/// LAB-040 Commerce Without Tricks: buy, restore, refund, pending approval, and offline
/// entitlement states over a local product fixtures and a local transaction-state
/// simulator. No button in this build creates a real charge.
///
/// Sensitive grants commit through `CommerceBackend` into `OperationService` as the app UI.
/// Unverified transactions never produce a `VerifiedEntitlement` and never write the store.
public enum CommerceWithoutTricks {
    public static let experimentID = "LAB-040"
    public static let title = "Commerce Without Tricks"
    public static let symbol = "cart"

    /// Every purchase control in this build is a simulator action. Linking StoreKit for a live
    /// `Product.purchase` is out of scope for the default build (LAB-040-A).
    public static let createsRealCharge = false

    /// Shown above every purchase control so the charge boundary is visible before a tap.
    public static let chargeBoundaryLabel =
        "This build uses the local transaction-state simulator. No button creates a real charge."
}
