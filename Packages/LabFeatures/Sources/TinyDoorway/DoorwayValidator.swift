import Foundation
import LabDomain

/// Parses and validates an untrusted doorway URL into a sealed proposal, the local info page, or a
/// refusal. It never opens the store, issues a grant, or builds a `DomainOperation`.
public enum DoorwayValidator {
    /// Validates `context.rawURL` under the doorway policy.
    public static func validate(_ context: InvocationContext) -> DoorwayValidation {
        let trimmed = context.rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return .refused(.malformedLink)
        }
        guard let scheme = url.scheme?.lowercased() else { return .refused(.malformedLink) }

        if url.user() != nil || url.password() != nil {
            return .refused(.linkContainsCredentials)
        }

        let channel: InvocationChannel
        let host: String
        switch scheme {
        case DoorwayPolicy.httpsScheme:
            channel = .universalLink
            guard let h = url.host(), !h.isEmpty else { return .refused(.malformedLink) }
            guard h.caseInsensitiveCompare(DoorwayPolicy.httpsHost) == .orderedSame else {
                return .refused(.untrustedHost(h))
            }
            host = DoorwayPolicy.httpsHost
            // Offline: https invocations cannot pretend to reach a hosted App Clip or AASA file.
            // The person still has the local deep link and the in-app information page.
            if context.reachability == .offline {
                return .refused(.offline(fallback: DoorwayFallback.offlineExplanation))
            }
        case DoorwayPolicy.deepLinkScheme:
            channel = .deepLink
            guard let h = url.host(), !h.isEmpty else { return .refused(.malformedLink) }
            guard h.caseInsensitiveCompare(DoorwayPolicy.deepLinkHost) == .orderedSame else {
                return .refused(.untrustedHost(h))
            }
            host = DoorwayPolicy.deepLinkHost
        default:
            return .refused(.unsupportedScheme(scheme))
        }

        let path = normalizedPath(url.path)
        let segments = path.split(separator: "/").map(String.init)

        for segment in segments where DoorwayPolicy.privilegedPathSegments.contains(segment.lowercased()) {
            return .refused(.privilegedAction(segment))
        }

        if path == DoorwayPolicy.infoPath || path == "/info/" {
            return .informationPage(channel)
        }

        guard path.hasPrefix(DoorwayPolicy.openPrefix) else {
            return .refused(.unknownPath(path.isEmpty ? "/" : path))
        }

        let actionName = String(path.dropFirst(DoorwayPolicy.openPrefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !actionName.isEmpty else { return .refused(.unknownPath(path)) }
        if actionName.contains("/") {
            return .refused(.unknownPath(path))
        }
        guard actionName == DoorwayPolicy.visitAction else {
            return .refused(.privilegedAction(actionName))
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var itemValue: String?
        for item in items {
            let name = item.name.lowercased()
            if DoorwayPolicy.privilegedQueryKeys.contains(name) {
                return .refused(.privilegedAction(name))
            }
            guard DoorwayPolicy.allowedQueryKeys.contains(name) else {
                return .refused(.untrustedParameter(item.name))
            }
            if name == "item" {
                guard itemValue == nil else { return .refused(.untrustedParameter("item")) }
                itemValue = item.value
            }
        }
        guard let rawItem = itemValue, let uuid = UUID(uuidString: rawItem) else {
            return .refused(.missingItem)
        }
        let itemID = ItemID(rawValue: uuid)
        guard DoorwayPolicy.allowedItemIDs.contains(itemID) else {
            return .refused(.itemUnavailable(uuid.uuidString))
        }

        // App Clip source without a configured clip: still validate the URL shape, but surface the
        // clip status when the host asks. Validation itself succeeds so the full-app path can run.
        if context.source == .appClip, case .notConfigured(let reason) = DoorwayClipStatus.current {
            return .refused(.clipUnavailable(reason))
        }

        let canonical = canonicalURL(scheme: scheme, host: host, path: "/open/visit", itemID: itemID)
        let proposal = SignedLinkProposal(
            action: .visit,
            itemID: itemID,
            channel: channel,
            canonicalURL: canonical,
            context: context
        )
        return .proposal(proposal)
    }

    private static func normalizedPath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        if path != "/", path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }

    private static func canonicalURL(scheme: String, host: String, path: String, itemID: ItemID) -> String {
        "\(scheme)://\(host)\(path)?item=\(itemID.rawValue.uuidString.lowercased())"
    }
}
