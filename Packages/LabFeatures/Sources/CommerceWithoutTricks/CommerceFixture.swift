import Foundation
import LabDomain

/// The original local product fixtures this experiment owns. Product identifiers, display
/// names, and terms are fixture data only. They mirror what a StoreKit Configuration file would
/// declare for testing; they are not App Store listings and never create a charge.
public enum CommerceFixture {
    public static let collection = CollectionID(rawValue: UUID(uuidString: "04004004-1040-4040-8040-040040040041")!)
    public static let collectionTitle = "Commerce Without Tricks"

    public static let createCollectionRequest = RequestID(rawValue: UUID(uuidString: "04004004-1040-4040-8040-0400400400C1")!)

    /// One-time unlock used by every default path in the desk.
    public static let notebook = CommerceProduct(
        id: ProductID(rawValue: "lab.commerce.field-notebook"),
        itemID: ItemID(rawValue: UUID(uuidString: "04004004-1040-4040-8040-040040040051")!),
        displayName: "Field Notebook Unlock",
        displayPrice: "$0.00 (simulated)",
        terms: "Simulated one-time unlock of the demo Field Notebook templates. No real charge. Grants a local demo entitlement only. Restorable from this screen's session history without an Apple Account."
    )

    /// A second product so restore and offline paths can show more than one entitlement.
    public static let compass = CommerceProduct(
        id: ProductID(rawValue: "lab.commerce.sample-compass"),
        itemID: ItemID(rawValue: UUID(uuidString: "04004004-1040-4040-8040-040040040052")!),
        displayName: "Sample Compass Overlay",
        displayPrice: "$0.00 (simulated)",
        terms: "Simulated one-time unlock of the demo Sample Compass overlay. No real charge. Grants a local demo entitlement only. Restorable from this screen's session history without an Apple Account."
    )

    public static let products: [CommerceProduct] = [notebook, compass]

    public static func product(id: ProductID) -> CommerceProduct? {
        products.first { $0.id == id }
    }


}

/// A product from the local product fixtures. Names and terms are what the person sees.
public struct CommerceProduct: Hashable, Sendable, Identifiable {
    public let id: ProductID
    public let itemID: ItemID
    public let displayName: String
    public let displayPrice: String
    public let terms: String
}

/// A StoreKit-style product identifier. It is a string, never a display name.
public struct ProductID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}
