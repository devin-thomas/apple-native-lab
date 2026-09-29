import AppIntents
import Foundation
import LabDomain
import UniformTypeIdentifiers

/// What an intent returns besides its typed value: the sentence the system shows, built from
/// the receipt when there is one.
public struct IntentOutput<Value: Sendable>: Sendable {
    public let value: Value
    public let dialog: String
    /// The receipt of the change, or `nil` for a read.
    public let receipt: ActionReceipt?

    init(value: Value, dialog: String) {
        self.value = value
        self.dialog = dialog
        receipt = nil
    }

    init(value: Value, receipt: ActionReceipt) {
        self.value = value
        self.receipt = receipt
        dialog = receipt.undo == nil
            ? receipt.summary
            : "\(receipt.summary) Its receipt in Native Lab offers an undo."
    }
}

// Every intent below is a thin adapter: `perform()` adds only the system's dialogs and hands the
// work to `run(with:)`, which calls `ActionAtlasActions` as an App Intent. The in-app action
// browser calls the same actions as the app UI. Each intent requires an unlocked device, because
// the lab may hold the person's own collections.

// MARK: - Create

public struct CreateCollectionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Lab Collection"
    public static let description = IntentDescription(
        "Creates one of your own collections in Native Lab. The change leaves a receipt in the app with an undo."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Title")
    public var title: String

    @Parameter(
        title: "Request ID",
        description: "Optional. Running again with the same request ID returns the first result instead of creating another collection."
    )
    public var requestID: String?

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Create lab collection \(\.$title)") {
            \.$requestID
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabCollectionEntity> & ProvidesDialog {
        let output = try await run(with: atlas)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    /// The intent's work without the system: create the collection as an App Intent.
    public func run(with link: ActionAtlasLink) async throws(ActionAtlasError) -> IntentOutput<LabCollectionEntity> {
        let outcome = try await link.actions(.appIntent).createCollection(title: title, request: AtlasRequest(text: requestID))
        return IntentOutput(value: LabCollectionEntity(outcome.entity), receipt: outcome.receipt)
    }
}

public struct CreateItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Lab Item"
    public static let description = IntentDescription(
        "Creates an item in one of your own collections. With no collection given, your only collection is used, or you are asked which one."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Title")
    public var title: String

    @Parameter(title: "Note")
    public var note: String?

    @Parameter(
        title: "Collection",
        description: "One of your own collections. Demo collections hold only the samples.",
        optionsProvider: OwnCollectionOptions()
    )
    public var collection: LabCollectionEntity?

    @Parameter(
        title: "Request ID",
        description: "Optional. Running again with the same request ID returns the first result instead of creating another item."
    )
    public var requestID: String?

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Create lab item \(\.$title) in \(\.$collection)") {
            \.$note
            \.$requestID
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog {
        let parameter = $collection
        let itemTitle = title
        let output = try await run(with: atlas) { candidates in
            let chosen = try await parameter.requestDisambiguation(
                among: candidates.map(LabCollectionEntity.init),
                dialog: "Which of your collections should hold “\(itemTitle)”?"
            )
            guard let match = candidates.first(where: { $0.id.rawValue == chosen.id }) else {
                throw ActionAtlasError.missingCollection(CollectionID(rawValue: chosen.id))
            }
            return match
        }
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    /// The intent's work without the system. `choose` stands in for the system's disambiguation
    /// when several of the person's collections could hold the item.
    public func run(with link: ActionAtlasLink, choose: AtlasChooser<LabCollection>? = nil) async throws -> IntentOutput<LabItemEntity> {
        let actions = link.actions(.appIntent)
        let outcome = try await actions.createItem(
            title: title, note: note ?? "", in: collection?.collectionID,
            request: try AtlasRequest(text: requestID), choose: choose
        )
        let entity = try await ItemLookup(actions: actions).entities([outcome.entity])
        return IntentOutput(value: entity[0], receipt: outcome.receipt)
    }
}

// MARK: - Find

public struct FindItemsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Lab Items"
    public static let description = IntentDescription(
        "Finds lab items whose title or note contains the text, ignoring case and accents, ordered by title."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Text", description: "Leave empty to list items without filtering by text.")
    public var text: String?

    @Parameter(title: "Collection")
    public var collection: LabCollectionEntity?

    @Parameter(title: "Include Archived", default: false)
    public var includeArchived: Bool

    @Parameter(title: "Limit", description: "At most this many items, from 1 to 200.", default: 20)
    public var limit: Int

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Find lab items matching \(\.$text) in \(\.$collection)") {
            \.$includeArchived
            \.$limit
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[LabItemEntity]> & ProvidesDialog {
        let output = try await run(with: atlas)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    public func run(with link: ActionAtlasLink) async throws(ActionAtlasError) -> IntentOutput<[LabItemEntity]> {
        let actions = link.actions(.appIntent)
        let items = try await actions.findItems(
            text: text, in: collection?.collectionID, includeArchived: includeArchived, limit: limit
        )
        let entities = try await ItemLookup(actions: actions).entities(items)
        let dialog = switch entities.count {
        case 0: "No lab items matched."
        case 1: "Found 1 lab item."
        default: "Found \(entities.count) lab items."
        }
        return IntentOutput(value: entities, dialog: dialog)
    }
}

public struct GetItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Lab Item"
    public static let description = IntentDescription("Reads the current state of one lab item.")
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Item")
    public var item: LabItemEntity

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$item)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog {
        let output = try await run(with: atlas)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    public func run(with link: ActionAtlasLink) async throws(ActionAtlasError) -> IntentOutput<LabItemEntity> {
        let actions = link.actions(.appIntent)
        let current = try await actions.item(item.itemID)
        let entity = try await ItemLookup(actions: actions).entities([current])[0]
        return IntentOutput(value: entity, dialog: "“\(entity.title)” is at revision \(entity.revision)\(entity.isArchived ? ", archived" : "").")
    }
}

// MARK: - Change

public struct UpdateItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Update Lab Item"
    public static let description = IntentDescription(
        "Replaces a lab item's title, note, or both. If the item changed since it was picked, nothing is overwritten."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Item")
    public var item: LabItemEntity

    @Parameter(title: "New Title")
    public var newTitle: String?

    @Parameter(title: "New Note")
    public var newNote: String?

    @Parameter(
        title: "Request ID",
        description: "Optional. Running again with the same request ID returns the first result instead of changing the item again."
    )
    public var requestID: String?

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Update \(\.$item)") {
            \.$newTitle
            \.$newNote
            \.$requestID
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog {
        let output = try await run(with: atlas)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    public func run(with link: ActionAtlasLink) async throws(ActionAtlasError) -> IntentOutput<LabItemEntity> {
        let actions = link.actions(.appIntent)
        let outcome = try await actions.updateItem(
            item.itemID, expected: try item.expectedRevision(), title: newTitle, note: newNote,
            request: try AtlasRequest(text: requestID)
        )
        let entity = try await ItemLookup(actions: actions).entities([outcome.entity])[0]
        return IntentOutput(value: entity, receipt: outcome.receipt)
    }
}

public struct ArchiveItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Archive Lab Item"
    public static let description = IntentDescription(
        "Archives a lab item after you confirm. Nothing is deleted, and the receipt in Native Lab offers an undo."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Item")
    public var item: LabItemEntity

    @Parameter(
        title: "Request ID",
        description: "Optional. Running again with the same request ID returns the first result instead of archiving again."
    )
    public var requestID: String?

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Archive \(\.$item)") {
            \.$requestID
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog {
        // The system's confirmation is the only step that lets this intent archive. If the person
        // cancels, requestConfirmation throws, the error propagates, and nothing is committed.
        let output = try await run(with: atlas) { prompt in
            try await requestConfirmation(
                actionName: .custom(
                    acceptLabel: "Archive", acceptAlternatives: [],
                    denyLabel: "Cancel", denyAlternatives: [],
                    destructive: true
                ),
                dialog: "\(prompt.text)"
            )
        }
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    /// The intent's work without the system. `confirm` stands in for the system's confirmation.
    public func run(
        with link: ActionAtlasLink,
        confirm: @Sendable (ArchivePrompt) async throws -> Void
    ) async throws -> IntentOutput<LabItemEntity> {
        let actions = link.actions(.appIntent)
        let outcome = try await actions.archiveItem(
            item.itemID, expected: try item.expectedRevision(), request: try AtlasRequest(text: requestID), confirm: confirm
        )
        let entity = try await ItemLookup(actions: actions).entities([outcome.entity])[0]
        return IntentOutput(value: entity, receipt: outcome.receipt)
    }
}

public struct RestoreItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Restore Lab Item"
    public static let description = IntentDescription("Returns an archived lab item to normal view.")
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Item")
    public var item: LabItemEntity

    @Parameter(
        title: "Request ID",
        description: "Optional. Running again with the same request ID returns the first result instead of restoring again."
    )
    public var requestID: String?

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Restore \(\.$item)") {
            \.$requestID
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<LabItemEntity> & ProvidesDialog {
        let output = try await run(with: atlas)
        return .result(value: output.value, dialog: "\(output.dialog)")
    }

    public func run(with link: ActionAtlasLink) async throws(ActionAtlasError) -> IntentOutput<LabItemEntity> {
        let actions = link.actions(.appIntent)
        let outcome = try await actions.restoreItem(
            item.itemID, expected: try item.expectedRevision(), request: try AtlasRequest(text: requestID)
        )
        let entity = try await ItemLookup(actions: actions).entities([outcome.entity])[0]
        return IntentOutput(value: entity, receipt: outcome.receipt)
    }
}

// MARK: - Export

/// The representations Export Lab Item offers in Shortcuts.
public enum ItemExportFormat: String, AppEnum {
    case json
    case plainText

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Export Format"
    public static let caseDisplayRepresentations: [ItemExportFormat: DisplayRepresentation] = [
        .json: "JSON",
        .plainText: "Plain Text",
    ]

    var atlasFormat: AtlasExportFormat {
        switch self {
        case .json: .json
        case .plainText: .plainText
        }
    }
}

public struct ExportItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Export Lab Item"
    public static let description = IntentDescription(
        "Returns one lab item as a portable document: a versioned JSON file or plain text with its title, note, status, and collection. Nothing is uploaded."
    )
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Item")
    public var item: LabItemEntity

    @Parameter(title: "Format", default: .json)
    public var format: ItemExportFormat

    @Dependency(default: ActionAtlasLink.unavailable) private var atlas: ActionAtlasLink

    public static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$item) as \(\.$format)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let output = try await run(with: atlas)
        let file = IntentFile(data: output.value.data, filename: output.value.filename, type: Self.contentType(output.value.format))
        return .result(value: file, dialog: "\(output.dialog)")
    }

    public func run(with link: ActionAtlasLink) async throws(ActionAtlasError) -> IntentOutput<AtlasExport> {
        let export = try await link.actions(.appIntent).exportItem(item.itemID, as: format.atlasFormat)
        return IntentOutput(value: export, dialog: "Exported “\(export.document.title)” as \(export.format.title).")
    }

    static func contentType(_ format: AtlasExportFormat) -> UTType {
        switch format {
        case .json: .json
        case .plainText: .utf8PlainText
        }
    }
}

// MARK: - Package

/// Lets a host app include these intents in its App Intents metadata.
public struct ActionAtlasIntentsPackage: AppIntentsPackage {}
