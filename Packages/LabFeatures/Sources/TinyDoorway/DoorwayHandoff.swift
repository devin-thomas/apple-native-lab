import Foundation
import LabDomain

/// Confirmed visit state the App Clip (when configured) can hand to the full app.
///
/// A value snapshot only: item ID, seal of the proposal that was confirmed, and when. It is not a
/// grant and cannot invent an operation. The full app re-validates before showing the sample.
public struct DoorwayHandoff: Hashable, Sendable, Codable {
    public let itemID: ItemID
    public let seal: ContentDigest
    public let confirmedAt: Date
    public let channel: InvocationChannel

    public init(itemID: ItemID, seal: ContentDigest, confirmedAt: Date, channel: InvocationChannel) {
        self.itemID = itemID
        self.seal = seal
        self.confirmedAt = confirmedAt
        self.channel = channel
    }

    public init(proposal: SignedLinkProposal, confirmedAt: Date = Date()) {
        self.init(
            itemID: proposal.itemID,
            seal: proposal.seal,
            confirmedAt: confirmedAt,
            channel: proposal.channel
        )
    }

    private enum CodingKeys: String, CodingKey {
        case itemID, seal, confirmedAt, channel
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let uuid = try box.decode(UUID.self, forKey: .itemID)
        let sealHex = try box.decode(String.self, forKey: .seal)
        guard let seal = ContentDigest(hex: sealHex) else {
            throw DecodingError.dataCorruptedError(forKey: .seal, in: box, debugDescription: "seal")
        }
        self.itemID = ItemID(rawValue: uuid)
        self.seal = seal
        self.confirmedAt = try box.decode(Date.self, forKey: .confirmedAt)
        self.channel = try box.decode(InvocationChannel.self, forKey: .channel)
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(itemID.rawValue, forKey: .itemID)
        try box.encode(seal.hex, forKey: .seal)
        try box.encode(confirmedAt, forKey: .confirmedAt)
        try box.encode(channel, forKey: .channel)
    }
}

/// Original fixture links for the experiment UI and tests. Every URL is synthetic.
public enum DemoLinks {
    /// Happy-path https visit of Quartz point.
    public static let visitHTTPS =
        "https://doorway.nativelab.example/open/visit?item=af451890-ca80-4de9-b18b-4007066c9177"
    /// Happy-path deep link of the same sample.
    public static let visitDeepLink =
        "nativelab://doorway/open/visit?item=af451890-ca80-4de9-b18b-4007066c9177"
    /// Local information page (https shape).
    public static let infoHTTPS = "https://doorway.nativelab.example/info"
    /// Local information page (deep link).
    public static let infoDeepLink = "nativelab://doorway/info"

    public static let fixtures: [(name: String, url: String)] = [
        ("Visit Quartz (https)", visitHTTPS),
        ("Visit Quartz (deep link)", visitDeepLink),
        ("Information page (https)", infoHTTPS),
        ("Information page (deep link)", infoDeepLink),
    ]
}
