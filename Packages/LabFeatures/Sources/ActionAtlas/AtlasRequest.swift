import Foundation
import LabDomain

/// One requested decision, reused on every retry so it commits at most once (ADR-004).
///
/// A creation names its new entity by an ID derived from the request ID, so a retry repeats the
/// same operation and gets the recorded receipt back instead of making a second entity. The
/// in-app browser keeps one request per filled-in form; a shortcut may pass its own ID.
public struct AtlasRequest: Hashable, Sendable {
    public let id: RequestID

    public init(_ id: RequestID = RequestID()) {
        self.id = id
    }

    /// A request ID a shortcut supplies as text, or a new one when the text is empty or absent.
    public init(text: String?) throws(ActionAtlasError) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            self.init()
            return
        }
        guard let uuid = UUID(uuidString: trimmed) else { throw .invalidRequestID }
        self.init(RequestID(rawValue: uuid))
    }

    /// The ID a collection created by this request gets, the same on every retry.
    public var newCollectionID: CollectionID { CollectionID(rawValue: derived(salt: 0xC3)) }

    /// The ID an item created by this request gets, the same on every retry.
    public var newItemID: ItemID { ItemID(rawValue: derived(salt: 0x5A)) }

    /// The request's UUID with every byte flipped by `salt`, keeping the version and variant bits,
    /// so each kind of new entity gets a distinct, stable, well-formed identifier.
    private func derived(salt: UInt8) -> UUID {
        var bytes = id.rawValue.uuid
        withUnsafeMutableBytes(of: &bytes) { raw in
            for index in raw.indices {
                switch index {
                case 6: raw[index] ^= salt & 0x0F
                case 8: raw[index] ^= salt & 0x3F
                default: raw[index] ^= salt
                }
            }
        }
        return UUID(uuid: bytes)
    }
}
