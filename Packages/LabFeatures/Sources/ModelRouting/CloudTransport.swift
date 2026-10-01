/// A transport that could send a Private Cloud Compute request.
///
/// The live CoreLocal build uses `RefusingCloudTransport`: it never sends. Tests inject a
/// `CountingCloudTransport` to prove cloud-off causes zero sends, and that exhausted quota never
/// reaches a paid alternative.
public protocol CloudTransport: Sendable {
    /// How many send attempts reached this transport.
    var requestCount: Int { get async }
    /// Sends only when the caller has already checked policy, entitlement, quota, and consent.
    func send(_ preview: OutgoingFieldPreview) async throws -> CloudSendResult
}

public struct CloudSendResult: Hashable, Sendable {
    public let accepted: Bool
    public let detail: String

    public init(accepted: Bool, detail: String) {
        self.accepted = accepted
        self.detail = detail
    }
}

/// Never sends. The CoreLocal default: observing PCC does not open a network path.
public actor RefusingCloudTransport: CloudTransport {
    private var count = 0

    public init() {}

    public var requestCount: Int { count }

    public func send(_ preview: OutgoingFieldPreview) async throws -> CloudSendResult {
        count += 1
        return CloudSendResult(
            accepted: false,
            detail: "CoreLocal refuses Private Cloud Compute sends. The outgoing fields were \(preview.fields.count) named fields; nothing left this device."
        )
    }
}

/// Counts every send. Used in tests to prove cloud-off never calls it, and that quota exhaustion
/// never redirects to another provider.
public actor CountingCloudTransport: CloudTransport {
    private var count = 0
    private var lastPreview: OutgoingFieldPreview?

    public init() {}

    public var requestCount: Int { count }
    public var lastOutgoing: OutgoingFieldPreview? { lastPreview }

    public func send(_ preview: OutgoingFieldPreview) async throws -> CloudSendResult {
        count += 1
        lastPreview = preview
        return CloudSendResult(accepted: true, detail: "Counted cloud send of \(preview.fields.count) fields.")
    }

    public func reset() {
        count = 0
        lastPreview = nil
    }
}

/// A paid third-party provider is intentionally not modeled. Exhausted PCC quota must never
/// construct or call one.
public enum PaidProvider: Sendable {
    /// Always empty. A test fails if the module gains a paid-provider adapter.
    public static let supportedProviders: [String] = []

    public static var isOffered: Bool { !supportedProviders.isEmpty }
}
