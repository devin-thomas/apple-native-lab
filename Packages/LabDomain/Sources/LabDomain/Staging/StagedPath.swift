import Foundation

/// A validated, relative name for a file inside one import, such as `notes/today.txt`.
///
/// It comes from untrusted input (an archive entry, a shared file's name), so it is validated
/// from its raw bytes: strict UTF-8 (no overlong or surrogate encodings), no NUL or control
/// characters, no absolute start, no `.` or `..` component, no backslash, no character that is or
/// normalizes (NFKC) to a separator or to `.`/`..`, no bidirectional or invisible formatting
/// characters, and length and depth within the import limits. The staging area never uses it as
/// a file-system path: staged files are stored under their position, and the name is metadata.
///
/// A path is a person's file name, so it is private. `description`, `debugDescription`, and
/// reflection print a placeholder, so interpolating one into a message by accident leaks nothing.
public struct StagedPath: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The path in Unicode NFC, components joined by `/`.
    public let value: String
    public let components: [String]

    public init(_ raw: String, limits: ImportLimits = .standard) throws(PathRejection) {
        try self.init(bytes: Array(raw.utf8), limits: limits)
    }

    /// - Parameter isDirectory: Accept one trailing `/`, as archive folder entries have.
    public init(bytes: some Collection<UInt8>, isDirectory: Bool = false, limits: ImportLimits = .standard) throws(PathRejection) {
        guard !bytes.isEmpty else { throw .empty }
        guard bytes.count <= limits.maximumPathBytes else { throw .tooLong }
        guard !bytes.contains(0) else { throw .nul }
        guard case .success(var text) = StrictUTF8.decode(bytes) else { throw .invalidUTF8 }
        if isDirectory, text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { throw .empty }
        if text.hasPrefix("/") || Self.startsWithDrive(text) { throw .absolute }
        for scalar in text.unicodeScalars {
            if let rejection = Self.rejection(for: scalar) { throw rejection }
        }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= limits.maximumNestingDepth else { throw .tooDeep }
        for part in parts {
            switch part {
            case "": throw .emptyComponent
            case ".": throw .currentReference
            case "..": throw .parentReference
            default: break
            }
            guard part.utf8.count <= limits.maximumComponentBytes else { throw .componentTooLong }
            let compatible = part.precomposedStringWithCompatibilityMapping
            if compatible.unicodeScalars.contains(where: { Self.separators.contains($0) }) { throw .lookalikeSeparator }
            if compatible == "." || compatible == ".." { throw .lookalikeDot }
        }
        components = parts.map(\.precomposedStringWithCanonicalMapping)
        value = components.joined(separator: "/")
    }

    /// The form two names share when a case-insensitive, normalization-insensitive file system
    /// (such as default APFS) would treat them as the same file.
    var collisionKey: String {
        value.folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping
    }

    /// The lowercase extension of the last component, or `""`.
    public var pathExtension: String {
        guard let last = components.last, let dot = last.lastIndex(of: "."), dot != last.startIndex else { return "" }
        return String(last[last.index(after: dot)...]).lowercased()
    }

    public var description: String { "StagedPath(<\(components.count) private components>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }

    // MARK: Rules

    private static let separators: Set<Unicode.Scalar> = ["/", "\\", ":"]

    /// Characters that act as, or look like, a path separator on some system: slashes, the
    /// colon (the classic Mac OS separator, shown as `/` in Finder), and their lookalikes.
    private static let lookalikeSeparators: Set<Unicode.Scalar> = [
        ":", "\u{2044}", "\u{2215}", "\u{2216}", "\u{2236}", "\u{2571}", "\u{2572}", "\u{27CB}", "\u{27CD}",
        "\u{29F5}", "\u{29F8}", "\u{29F9}", "\u{A789}", "\u{FE13}", "\u{FE55}", "\u{FE68}", "\u{FF0F}",
        "\u{FF1A}", "\u{FF3C}",
    ]

    private static let bidiControls: Set<Unicode.Scalar> = [
        "\u{061C}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ]

    private static let invisibles: Set<Unicode.Scalar> = [
        "\u{00AD}", "\u{034F}", "\u{115F}", "\u{1160}", "\u{180E}", "\u{200B}", "\u{200C}", "\u{200D}",
        "\u{2060}", "\u{3164}", "\u{FEFF}", "\u{FFA0}",
    ]

    private static func rejection(for scalar: Unicode.Scalar) -> PathRejection? {
        if scalar == "\\" { return .backslash }
        if scalar.properties.generalCategory == .control { return .controlCharacter }
        if bidiControls.contains(scalar) { return .bidiControl }
        if invisibles.contains(scalar) || scalar.properties.generalCategory == .format { return .invisibleCharacter }
        if lookalikeSeparators.contains(scalar) { return .lookalikeSeparator }
        return nil
    }

    private static func startsWithDrive(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars.prefix(2))
        return scalars.count == 2 && scalars[1] == ":" && scalars[0].isASCII && scalars[0].properties.isAlphabetic
    }
}

/// Detects names that a case-insensitive, normalization-insensitive file system would merge, and
/// a file that shares its name with a folder another entry needs.
public struct StagedPathSet: Sendable {
    private var files: Set<String> = []
    private var folders: Set<String> = []

    public init() {}

    /// `false` when the path collides with one already inserted.
    public mutating func insert(_ path: StagedPath, isDirectory: Bool) -> Bool {
        let key = path.collisionKey
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        var prefixes: [String] = []
        for count in parts.indices.dropLast() {
            prefixes.append(parts[...count].joined(separator: "/"))
        }
        if prefixes.contains(where: files.contains) { return false }
        if isDirectory {
            guard !files.contains(key) else { return false }
            folders.insert(key)
        } else {
            guard !files.contains(key), !folders.contains(key) else { return false }
            files.insert(key)
        }
        folders.formUnion(prefixes)
        return true
    }
}
