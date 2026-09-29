import Foundation

/// Why a file name or archive entry name was refused.
public enum PathRejection: String, Error, Hashable, Sendable, CaseIterable {
    case empty
    case tooLong = "too-long"
    case componentTooLong = "component-too-long"
    case tooDeep = "too-deep"
    /// Starts at a root: `/`, or a drive such as `C:`.
    case absolute
    /// A `..` component, which would leave the import's folder.
    case parentReference = "parent-reference"
    /// A `.` component.
    case currentReference = "current-reference"
    /// Two separators in a row, such as `a//b`.
    case emptyComponent = "empty-component"
    case backslash
    case nul
    case controlCharacter = "control-character"
    /// Bytes that are not valid UTF-8, including overlong encodings such as `C0 AF` for `/`.
    case invalidUTF8 = "invalid-utf8"
    /// A character that is, or normalizes to, a separator: fullwidth or division slashes, a colon.
    case lookalikeSeparator = "lookalike-separator"
    /// A component that normalizes to `.` or `..`, such as fullwidth full stops or a two-dot leader.
    case lookalikeDot = "lookalike-dot"
    /// A right-to-left override or other bidirectional control, which can disguise an extension.
    case bidiControl = "bidi-control"
    /// A zero-width or other invisible character.
    case invisibleCharacter = "invisible-character"

    var phrase: String {
        switch self {
        case .empty: "has no name"
        case .tooLong: "has a name that is too long"
        case .componentTooLong: "has a folder or file name that is too long"
        case .tooDeep: "is inside too many folders"
        case .absolute: "has a name that starts at the top of a disk"
        case .parentReference: "has a name that points outside the import (it contains “..”)"
        case .currentReference: "has a name with a “.” folder in it"
        case .emptyComponent: "has a name with an empty folder in it"
        case .backslash: "has a name with a backslash in it"
        case .nul: "has a name with a null character in it"
        case .controlCharacter: "has a name with a control character in it"
        case .invalidUTF8: "has a name that is not valid text"
        case .lookalikeSeparator: "has a name with a character that works or looks like a folder separator"
        case .lookalikeDot: "has a name made of characters that stand for “.” or “..”"
        case .bidiControl: "has a name with a hidden text-direction character that can disguise its type"
        case .invisibleCharacter: "has a name with an invisible character in it"
        }
    }
}

/// An archive feature this build does not accept.
public enum ArchiveFeature: String, Hashable, Sendable, CaseIterable {
    case encryption
    /// ZIP64 sizes or offsets. The import limits fit the 32-bit format, so none is needed.
    case zip64
    case multipleDisks = "multiple-disks"
    /// A compression method other than stored or deflate.
    case compressionMethod = "compression-method"
    /// Bytes before the first entry or after the directory, as in a self-extracting archive.
    case extraData = "extra-data"
}

/// Why an untrusted JSON document was refused. Offsets are byte positions, never content.
public enum StrictJSONError: Error, Hashable, Sendable {
    case empty
    case tooLarge(limit: Int)
    case invalidUTF8(offset: Int)
    case tooDeep(limit: Int)
    /// An object names the same key twice, including through escapes such as `a` for `a`,
    /// or through canonically equivalent Unicode.
    case duplicateKey(offset: Int)
    /// A `\u` escape for half of a surrogate pair without its other half.
    case unpairedSurrogate(offset: Int)
    case invalidSyntax(offset: Int)

    var code: String {
        switch self {
        case .empty: "empty"
        case .tooLarge: "too-large"
        case .invalidUTF8: "invalid-utf8"
        case .tooDeep: "too-deep"
        case .duplicateKey: "duplicate-key"
        case .unpairedSurrogate: "unpaired-surrogate"
        case .invalidSyntax: "invalid-syntax"
        }
    }

    var phrase: String {
        switch self {
        case .empty: "is empty"
        case .tooLarge(let limit): "is larger than \(ImportRejection.bytes(limit))"
        case .invalidUTF8: "contains bytes that are not valid text"
        case .tooDeep(let limit): "is nested more than \(limit) levels deep"
        case .duplicateKey: "names the same field twice"
        case .unpairedSurrogate: "contains a broken character escape"
        case .invalidSyntax: "is not valid JSON"
        }
    }
}

/// Why an import was refused, cancelled, or not adopted.
///
/// Every case is content-free: it names a position (`file` is 1-based, in the order the import
/// listed its files or the archive listed its entries) and a reason, never a file name, path,
/// or piece of the content. `userMessage` is a sentence a person can act on, `category` is what
/// diagnostics record, and `description` is a stable code, so logging an error by accident
/// still records nothing private. A refused import adopts nothing.
public enum ImportRejection: Error, Hashable, Sendable {
    // MARK: Lifecycle
    case cancelled
    /// No staged import has this ID. It may already have been added or removed.
    case notFound
    /// The staging folder could not be read or written.
    case stagingUnavailable
    case unreadableSource(file: Int)
    /// A folder, device, pipe, or other thing that is not an ordinary file.
    case unsupportedFileType(file: Int)

    // MARK: Text and links
    case emptyContent
    case textTooLarge(limit: Int)
    case malformedUTF8(offset: Int)
    /// Control characters other than line breaks and tabs.
    case unsupportedCharacters
    case titleTooLong(limit: Int)
    case linkTooLong(limit: Int)
    /// Only `http` and `https` links are accepted.
    case unsupportedLinkScheme
    case malformedLink
    /// A link with a user name or password in it.
    case linkContainsCredentials

    // MARK: Files
    case noFiles
    case tooManyFiles(limit: Int)
    case totalSizeTooLarge(limit: Int)
    case unsafePath(file: Int, PathRejection)
    /// The name matches an earlier file's, ignoring case and Unicode normalization, or makes a
    /// file and a folder share a name.
    case duplicatePath(file: Int)
    case malformedJSON(file: Int, StrictJSONError)

    // MARK: Archives
    case notAnArchive
    case unsupportedArchive(ArchiveFeature)
    case tooManyEntries(limit: Int)
    /// A symbolic or hard link entry, which could point outside the import.
    case linkEntry(file: Int)
    case unsupportedEntryType(file: Int)
    /// An archive inside the archive, found by its name or its first bytes.
    case nestedArchive(file: Int)
    case expandedSizeTooLarge(limit: Int)
    case compressionRatioTooHigh(file: Int, limit: Int)
    /// The entries together expand beyond the ratio, though each is small.
    case archiveRatioTooHigh(limit: Int)
    /// The entry produced more data than its header declared: a zip bomb that lies.
    case expandsBeyondDeclaredSize(file: Int)
    /// Two entries share bytes, as in an overlapping zip bomb.
    case overlappingEntries
    case corruptArchive
    case checksumMismatch(file: Int)

    // MARK: Staging records, read back by the app
    case recordTooLarge(limit: Int)
    case malformedRecord(StrictJSONError?)
    case unsupportedRecordFormat
    case unsupportedRecordVersion(Int)
    /// A field this record format does not define, such as a smuggled scope or grant.
    case unknownRecordField
    /// The record's content does not match its recorded digest or its folder.
    case digestMismatch
    /// A symbolic or hard link inside the staging folder.
    case linkedFileInStaging
    case unexpectedFileInStaging
    case missingStagedFile(file: Int)
    case stagedFileChanged(file: Int)

    // MARK: Adoption
    /// Files are checked and kept in staging, but this build has no attachment type to add them to.
    case attachmentsNotAdoptable
    case textTooLongForNote(limit: Int)
    case grantMissing
    case grantExpired
    case grantOutOfScope
    /// The adapter or policy does not allow this commit.
    case notAuthorized
    /// The chosen collection is missing, archived, or a demo collection.
    case destinationUnavailable
    /// Another request already used this import's identifiers differently.
    case identifierConflict
    case storeUnavailable
}

extension ImportRejection: LocalizedError, CustomStringConvertible {
    /// A sentence for the person importing, with no file name or content in it.
    public var userMessage: String {
        switch self {
        case .cancelled: "The import was cancelled. Nothing was added."
        case .notFound: "This import is no longer waiting. It may already have been added or removed."
        case .stagingUnavailable: "The import couldn’t be saved for review. Try sharing it again."
        case .unreadableSource(let file): "File \(file) couldn’t be read. Nothing was imported."
        case .unsupportedFileType(let file): "Item \(file) is not an ordinary file, so it can’t be imported."
        case .emptyContent: "There is nothing to import."
        case .textTooLarge(let limit): "The shared text is larger than \(Self.bytes(limit)), the most one import can hold."
        case .malformedUTF8: "The shared text contains bytes that are not valid text, so it wasn’t imported."
        case .unsupportedCharacters: "The shared text contains control characters that can’t be stored."
        case .titleTooLong(let limit): "The shared title is longer than \(Self.bytes(limit))."
        case .linkTooLong(let limit): "The shared link is longer than \(Self.bytes(limit))."
        case .unsupportedLinkScheme: "Only web links (http or https) can be imported."
        case .malformedLink: "The shared link is not a complete web address."
        case .linkContainsCredentials: "The shared link contains a user name or password, so it wasn’t imported."
        case .noFiles: "The import has no files."
        case .tooManyFiles(let limit): "The import has more than \(limit) files, the most one import can hold."
        case .totalSizeTooLarge(let limit): "The files together are larger than \(Self.bytes(limit)), the most one import can hold."
        case .unsafePath(let file, let reason): "Item \(file) \(reason.phrase), so the import was refused."
        case .duplicatePath(let file): "Item \(file) has the same name as an earlier item, so the import was refused."
        case .malformedJSON(let file, let reason): "File \(file) \(reason.phrase), so the import was refused."
        case .notAnArchive: "The file is not a ZIP archive."
        case .unsupportedArchive(let feature): Self.archiveMessage(feature)
        case .tooManyEntries(let limit): "The archive lists more than \(limit) entries, so it wasn’t opened."
        case .linkEntry(let file): "Item \(file) in the archive is a link to another location, so the archive was refused."
        case .unsupportedEntryType(let file): "Item \(file) in the archive is not an ordinary file or folder."
        case .nestedArchive(let file): "Item \(file) is another archive inside this one. Import it on its own."
        case .expandedSizeTooLarge(let limit): "The archive would expand to more than \(Self.bytes(limit)), so it wasn’t opened."
        case .compressionRatioTooHigh(let file, let limit):
            "Item \(file) in the archive expands more than \(limit) times its size, which is how zip bombs work, so the archive was refused."
        case .archiveRatioTooHigh(let limit):
            "The archive expands more than \(limit) times its size, which is how zip bombs work, so it was refused."
        case .expandsBeyondDeclaredSize(let file):
            "Item \(file) in the archive expanded beyond the size it declared, so the archive was refused."
        case .overlappingEntries: "Entries in the archive overlap each other, which is how some zip bombs work, so it was refused."
        case .corruptArchive: "The archive is damaged or incomplete."
        case .checksumMismatch(let file): "Item \(file) in the archive is damaged: its checksum doesn’t match."
        case .recordTooLarge, .malformedRecord, .unsupportedRecordFormat, .unknownRecordField, .digestMismatch,
             .linkedFileInStaging, .unexpectedFileInStaging, .missingStagedFile, .stagedFileChanged:
            "This waiting import was changed or damaged after it was shared, so it was set aside. Share it again."
        case .unsupportedRecordVersion: "This waiting import was saved by a newer version of the app."
        case .attachmentsNotAdoptable: "Files are checked and kept for review, but this version can’t add files to a collection yet."
        case .textTooLongForNote(let limit): "The shared text is longer than an item note can hold (\(limit) characters)."
        case .grantMissing: "Adding this import needs your approval. Review it and choose Add."
        case .grantExpired: "Your approval to add this import expired. Review it and choose Add again."
        case .grantOutOfScope: "Your approval covers a different change. Review this import and choose Add."
        case .notAuthorized: "This change isn’t allowed from here."
        case .destinationUnavailable: "The chosen collection can’t take new items. Choose another collection."
        case .identifierConflict: "This import conflicts with an earlier request. Share it again."
        case .storeUnavailable: "The import couldn’t be saved. Nothing was added. Try again."
        }
    }

    public var errorDescription: String? { userMessage }

    /// A stable, content-free code such as `unsafe-path/parent-reference`.
    public var code: String {
        switch self {
        case .cancelled: "cancelled"
        case .notFound: "not-found"
        case .stagingUnavailable: "staging-unavailable"
        case .unreadableSource: "unreadable-source"
        case .unsupportedFileType: "unsupported-file-type"
        case .emptyContent: "empty-content"
        case .textTooLarge: "text-too-large"
        case .malformedUTF8: "malformed-utf8"
        case .unsupportedCharacters: "unsupported-characters"
        case .titleTooLong: "title-too-long"
        case .linkTooLong: "link-too-long"
        case .unsupportedLinkScheme: "unsupported-link-scheme"
        case .malformedLink: "malformed-link"
        case .linkContainsCredentials: "link-contains-credentials"
        case .noFiles: "no-files"
        case .tooManyFiles: "too-many-files"
        case .totalSizeTooLarge: "total-size-too-large"
        case .unsafePath(_, let reason): "unsafe-path/\(reason.rawValue)"
        case .duplicatePath: "duplicate-path"
        case .malformedJSON(_, let reason): "malformed-json/\(reason.code)"
        case .notAnArchive: "not-an-archive"
        case .unsupportedArchive(let feature): "unsupported-archive/\(feature.rawValue)"
        case .tooManyEntries: "too-many-entries"
        case .linkEntry: "link-entry"
        case .unsupportedEntryType: "unsupported-entry-type"
        case .nestedArchive: "nested-archive"
        case .expandedSizeTooLarge: "expanded-size-too-large"
        case .compressionRatioTooHigh: "compression-ratio-too-high"
        case .archiveRatioTooHigh: "archive-ratio-too-high"
        case .expandsBeyondDeclaredSize: "expands-beyond-declared-size"
        case .overlappingEntries: "overlapping-entries"
        case .corruptArchive: "corrupt-archive"
        case .checksumMismatch: "checksum-mismatch"
        case .recordTooLarge: "record-too-large"
        case .malformedRecord(let reason): reason.map { "malformed-record/\($0.code)" } ?? "malformed-record"
        case .unsupportedRecordFormat: "unsupported-record-format"
        case .unsupportedRecordVersion: "unsupported-record-version"
        case .unknownRecordField: "unknown-record-field"
        case .digestMismatch: "digest-mismatch"
        case .linkedFileInStaging: "linked-file-in-staging"
        case .unexpectedFileInStaging: "unexpected-file-in-staging"
        case .missingStagedFile: "missing-staged-file"
        case .stagedFileChanged: "staged-file-changed"
        case .attachmentsNotAdoptable: "attachments-not-adoptable"
        case .textTooLongForNote: "text-too-long-for-note"
        case .grantMissing: "grant-missing"
        case .grantExpired: "grant-expired"
        case .grantOutOfScope: "grant-out-of-scope"
        case .notAuthorized: "not-authorized"
        case .destinationUnavailable: "destination-unavailable"
        case .identifierConflict: "identifier-conflict"
        case .storeUnavailable: "store-unavailable"
        }
    }

    public var description: String { code }

    public var category: DiagnosticCategory {
        switch self {
        case .cancelled: .cancelled
        case .notFound, .destinationUnavailable: .notFound
        case .stagingUnavailable, .unreadableSource: .unavailable
        case .storeUnavailable: .storeFailure
        case .unsupportedFileType, .unsupportedLinkScheme, .notAnArchive, .unsupportedArchive, .unsupportedEntryType,
             .unsupportedRecordVersion, .attachmentsNotAdoptable:
            .unsupported
        case .emptyContent, .unsupportedCharacters, .malformedLink, .linkContainsCredentials, .noFiles:
            .invalidInput
        case .textTooLarge, .titleTooLong, .linkTooLong, .tooManyFiles, .totalSizeTooLarge, .tooManyEntries,
             .expandedSizeTooLarge, .recordTooLarge, .textTooLongForNote:
            .tooLarge
        case .malformedUTF8, .malformedJSON, .malformedRecord, .unsupportedRecordFormat, .unknownRecordField:
            .malformedData
        case .unsafePath, .duplicatePath: .unsafePath
        case .linkEntry, .nestedArchive, .compressionRatioTooHigh, .archiveRatioTooHigh, .expandsBeyondDeclaredSize, .overlappingEntries,
             .corruptArchive, .checksumMismatch:
            .unsafeArchive
        case .digestMismatch, .linkedFileInStaging, .unexpectedFileInStaging, .missingStagedFile, .stagedFileChanged:
            .tamperedStaging
        case .grantMissing: .grantMissing
        case .grantExpired: .grantExpired
        case .grantOutOfScope: .grantOutOfScope
        case .notAuthorized: .unauthorized
        case .identifierConflict: .duplicate
        }
    }

    private static func archiveMessage(_ feature: ArchiveFeature) -> String {
        switch feature {
        case .encryption: "The archive is encrypted, so it can’t be checked before import."
        case .zip64: "The archive uses the ZIP64 format, which this version doesn’t accept."
        case .multipleDisks: "The archive is split across several files."
        case .compressionMethod: "The archive uses a compression method this version doesn’t accept."
        case .extraData: "The archive has extra data before or after its entries, so it was refused."
        }
    }

    /// A byte count in the units people read, such as “2 MB” or “1 GB”.
    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .binary)
    }
}
