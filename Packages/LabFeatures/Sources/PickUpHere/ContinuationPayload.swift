import Foundation
import LabDomain

/// The bytes a continuation is allowed to carry: three strings, and nothing else.
///
/// An activity dictionary or a link that adds a key is refused whole. Ignoring the extra key
/// would still have accepted a payload someone used to smuggle the draft's text, and the error
/// does not repeat the value.
enum ContinuationPayload {
    static let documentKey = "documentID"
    static let revisionKey = "revision"
    static let sectionKey = "section"
    static let keys: Set<String> = [documentKey, revisionKey, sectionKey]

    static func userInfo(for token: ContinuationToken) -> [String: String] {
        [
            documentKey: token.locator.documentID.rawValue.uuidString,
            revisionKey: String(token.locator.revision.rawValue),
            sectionKey: String(token.position.section),
        ]
    }

    static func token(from userInfo: [AnyHashable: Any]) throws(PickUpError) -> ContinuationToken {
        var values: [String: String] = [:]
        for (key, value) in userInfo {
            guard let name = key.base as? String, let text = value as? String else { throw .invalidPayload }
            values[name] = text
        }
        return try token(from: values)
    }

    static func token(from values: [String: String]) throws(PickUpError) -> ContinuationToken {
        guard Set(values.keys) == keys else { throw .invalidPayload }
        guard let idText = values[documentKey], let id = UUID(uuidString: idText) else { throw .invalidPayload }
        guard let revisionText = values[revisionKey], let revisionNumber = Int(revisionText),
              let revision = Revision(rawValue: revisionNumber) else { throw .invalidPayload }
        guard let sectionText = values[sectionKey], let sectionNumber = Int(sectionText) else { throw .invalidPayload }
        let position = try SectionPosition(section: sectionNumber)
        return ContinuationToken(
            locator: DocumentLocator(documentID: ItemID(rawValue: id), revision: revision),
            position: position
        )
    }
}

/// An explicit continuation link. It names the same three fields as the activity and is not a
/// request this app sends anywhere: a person copies it and pastes it on the other device.
public enum ContinuationLink {
    static let scheme = "nativelab"
    static let host = "continue"

    public static func url(for token: ContinuationToken) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        let info = ContinuationPayload.userInfo(for: token)
        components.queryItems = ContinuationPayload.keys.sorted().map { name in
            URLQueryItem(name: name, value: info[name])
        }
        return components.url!
    }

    public static func token(parsing url: URL) throws(PickUpError) -> ContinuationToken {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw .invalidPayload }
        guard components.scheme == scheme, components.host == host else { throw .invalidPayload }
        guard components.path.isEmpty || components.path == "/" else { throw .invalidPayload }
        guard let items = components.queryItems else { throw .invalidPayload }
        var values: [String: String] = [:]
        for item in items {
            guard ContinuationPayload.keys.contains(item.name), let value = item.value, values[item.name] == nil else {
                throw .invalidPayload
            }
            values[item.name] = value
        }
        return try ContinuationPayload.token(from: values)
    }
}
