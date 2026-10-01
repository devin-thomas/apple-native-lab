import Foundation
import LabDomain

/// A recipe export document, built under the CORE-006 export rule: text leaves only when the lab
/// wrote it.
///
/// `DiagnosticEvent` names can be made only from string literals, so runtime text can never
/// enter a diagnostics export. A recipe export applies the same rule to its text. It writes the
/// format, the recipe's ID, each step's order and kind, and the stable source item IDs. It writes
/// a title, a step's detail, or a model-step field name or value only when that string is exactly
/// text the lab ships in its bundled recipes (`LabAuthoredText`). Everything else a person or a
/// caller typed is withheld, whatever its field is called and whatever it holds, and the document
/// says where: a withheld value is written as `[withheld]`, and model-step fields whose names
/// were typed are only counted. No field name decides what is secret, so a new, renamed, or nested
/// field cannot carry a value out.
///
/// ```json
/// {
///   "format": "native-lab-recipe",
///   "formatVersion": 2,
///   "id": "<UUID>",
///   "title": "Query → Report",
///   "steps": [{ "order": 1, "kind": "query", "detail": "[withheld]" }, …],
///   "sourceItemIDs": ["<UUID>", …],
///   "modelStep": { "fields": { "prompt": "[withheld]" }, "withheldFieldCount": 1 }
/// }
/// ```
///
/// As with `DiagnosticExportPreview`, `text` is the complete export and `write(to:)` writes
/// exactly its bytes, so what a person reviews is the file they share.
public struct RecipeExport: Hashable, Sendable {
    public static let withheldPlaceholder = "[withheld]"

    /// What the export contains and leaves out, for the export screen and the manual fallback.
    public static let redactionNotes = [
        "Contains the recipe's ID, its steps' order and kind, and the IDs of the items it uses.",
        "Text is included only when Native Lab wrote it. Titles, queries, notes, and model-step fields you typed are withheld, whatever they are called.",
        "Withheld text is marked [withheld]; model-step fields with names you typed are counted, not named.",
        "Nothing is sent anywhere; you choose where the file goes.",
    ]

    /// The definition as the app holds it. It is never encoded; only `data` leaves the app.
    public let recipe: RecipeDefinition
    public let data: Data
    public let filename: String
    /// Where text was withheld. Built only from positions, counts, and lab-authored names.
    public let withheld: RecipeExportWithholding

    public init(recipe: RecipeDefinition) {
        let document = ExportDocument(recipe)
        self.recipe = recipe
        self.withheld = document.withholding
        self.data = Self.encode(document)
        self.filename = "\(Self.safeName(document.title)).recipe.json"
    }

    /// The title as it appears in the export, or a neutral name when the title was withheld.
    public var displayTitle: String {
        LabAuthoredText.contains(recipe.title) ? recipe.title : "Lab recipe"
    }

    /// Whether the encoded UTF-8 text contains any of the given values.
    public func containsRawSecret(_ secrets: [String]) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        return secrets.contains { !$0.isEmpty && text.contains($0) }
    }

    public var text: String { String(decoding: data, as: UTF8.self) }

    /// Writes exactly `data` to a new file at a location the person chose. It never replaces a
    /// file that already exists there.
    public func write(to url: URL) throws {
        try data.write(to: url, options: [.withoutOverwriting])
    }

    private static func encode(_ document: ExportDocument) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Every field is a fixed name, a UUID, an integer, or lab-authored text, so encoding
        // cannot fail; an empty document is still safe if it somehow did.
        return (try? encoder.encode(document)) ?? Data("{}".utf8)
    }

    private static func safeName(_ title: String?) -> String {
        guard let title else { return "Lab recipe" }
        let replaced = title.map { "/:\\".contains($0) ? Character("-") : $0 }
        var name = String(replaced).trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        if name.count > 60 { name = String(name.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "Lab recipe" : name
    }
}

/// Where a recipe export withheld text. Every part is a position, a count, or a name the lab
/// wrote, so this summary is itself safe to show in a Shortcuts dialog.
public struct RecipeExportWithholding: Hashable, Sendable {
    /// The recipe's title was typed, so the export carries `[withheld]` instead.
    public let title: Bool
    /// Orders of steps whose detail (query text or transform note) was withheld.
    public let stepDetails: [Int]
    /// Lab-authored model-step field names whose values were typed and withheld.
    public let modelStepValues: [String]
    /// Model-step fields whose names were typed. Neither name nor value is written.
    public let unnamedModelStepFields: Int

    public var isEmpty: Bool {
        !title && stepDetails.isEmpty && modelStepValues.isEmpty && unnamedModelStepFields == 0
    }

    /// One sentence for the export message, or `nil` when nothing was withheld.
    public var summary: String? {
        var parts: [String] = []
        if title { parts.append("the title") }
        if !stepDetails.isEmpty {
            let orders = stepDetails.map(String.init).joined(separator: ", ")
            parts.append("the text of step\(stepDetails.count == 1 ? "" : "s") \(orders)")
        }
        if !modelStepValues.isEmpty {
            parts.append("the model-step \(modelStepValues.joined(separator: ", ")) value\(modelStepValues.count == 1 ? "" : "s")")
        }
        if unnamedModelStepFields > 0 {
            let count = unnamedModelStepFields
            parts.append("\(count) model-step field\(count == 1 ? "" : "s") with typed names")
        }
        guard !parts.isEmpty else { return nil }
        return "Withheld \(parts.joined(separator: "; ")): only text Native Lab wrote leaves in an export."
    }
}

/// Text the lab itself wrote: every title, step detail, and model-step field name and value in
/// the bundled recipes. These come from string literals in this module, so none of them can be a
/// person's secret. A recipe export writes a string only when it is exactly one of these.
enum LabAuthoredText {
    static let all: Set<String> = {
        var text: Set<String> = []
        for recipe in WorkbenchRecipeCatalog.bundledRecipes {
            text.insert(recipe.title)
            for step in recipe.steps {
                if let detail = step.detail { text.insert(detail) }
            }
            for (key, value) in recipe.modelStep?.fields ?? [:] {
                text.insert(key)
                text.insert(value)
            }
        }
        return text
    }()

    /// Empty text carries nothing, so it is exported as is.
    static func contains(_ text: String) -> Bool { text.isEmpty || all.contains(text) }

    /// `text` when the lab wrote it, otherwise the withheld placeholder.
    static func exported(_ text: String) -> String {
        contains(text) ? text : RecipeExport.withheldPlaceholder
    }
}

/// Wire shape for a recipe export. Built field by field from the definition; nothing in the
/// definition is encoded directly.
private struct ExportDocument: Encodable {
    let format: String
    let formatVersion: Int
    let id: UUID
    let title: String?
    let steps: [StepWire]
    let sourceItemIDs: [UUID]
    let modelStep: ModelWire?
    let withholding: RecipeExportWithholding

    private enum CodingKeys: String, CodingKey {
        case format, formatVersion, id, title, steps, sourceItemIDs, modelStep
    }

    init(_ recipe: RecipeDefinition) {
        format = RecipeDefinition.format
        formatVersion = RecipeDefinition.formatVersion
        id = recipe.id.rawValue
        let titleIsLabText = LabAuthoredText.contains(recipe.title)
        title = titleIsLabText ? recipe.title : nil
        steps = recipe.steps.map(StepWire.init)
        sourceItemIDs = recipe.sourceItemIDs.map(\.rawValue)
        let model = recipe.modelStep.map(ModelWire.init)
        modelStep = model
        withholding = RecipeExportWithholding(
            title: !titleIsLabText,
            stepDetails: recipe.steps.filter { step in
                step.detail.map { !LabAuthoredText.contains($0) } ?? false
            }.map(\.order),
            modelStepValues: model?.withheldValueNames ?? [],
            unnamedModelStepFields: model?.withheldFieldCount ?? 0
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(id, forKey: .id)
        try container.encode(title ?? RecipeExport.withheldPlaceholder, forKey: .title)
        try container.encode(steps, forKey: .steps)
        try container.encode(sourceItemIDs, forKey: .sourceItemIDs)
        try container.encodeIfPresent(modelStep, forKey: .modelStep)
    }

    struct StepWire: Encodable {
        let order: Int
        let kind: String
        let detail: String?

        init(_ step: RecipeStep) {
            order = step.order
            kind = step.kind.rawValue
            detail = step.detail.map(LabAuthoredText.exported)
        }
    }

    struct ModelWire: Encodable {
        let view: ModelStepExportView

        private enum CodingKeys: String, CodingKey {
            case fields, withheldFieldCount
        }

        init(_ payload: ModelStepPayload) {
            view = ModelStepExportView(payload: payload)
        }

        var withheldValueNames: [String] { view.withheldValueNames }
        var withheldFieldCount: Int { view.withheldFieldCount }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(view.fields, forKey: .fields)
            if view.withheldFieldCount > 0 { try container.encode(view.withheldFieldCount, forKey: .withheldFieldCount) }
        }
    }
}

/// What an optional model step would receive. This is the in-app view: it shows the values a
/// person typed, masking secret-shaped field names as a display courtesy. Anything that leaves the
/// app (a recipe export, or the Inspect Model Step intent's result) follows `RecipeExport`'s rule
/// instead and carries no typed text at all.
public struct ModelStepInspection: Hashable, Sendable {
    public let fields: [String: String]
    public let redactedKeys: [String]
    public let summary: String

    public init(payload: ModelStepPayload) {
        let redacted = SecretRedaction.redact(payload.fields)
        fields = redacted
        redactedKeys = payload.fields.keys.filter { SecretRedaction.isSecretField($0) }.sorted()
        if redactedKeys.isEmpty {
            summary = "Model step would receive \(redacted.count) field\(redacted.count == 1 ? "" : "s"). No secret-shaped fields were present."
        } else {
            summary = "Model step would receive \(redacted.count) field\(redacted.count == 1 ? "" : "s"). Secret-shaped fields (\(redactedKeys.joined(separator: ", "))) are shown as \(SecretRedaction.placeholder) and are not stored in Shortcuts."
        }
    }
}

/// The part of a model-step inspection that may leave the app, under the export rule.
public struct ModelStepExportView: Hashable, Sendable {
    /// Lab-authored field names, each with its value or `[withheld]`.
    public let fields: [String: String]
    /// Fields whose names were typed; neither their names nor their values are written.
    public let withheldFieldCount: Int
    /// Lab-authored field names whose typed values were withheld.
    public let withheldValueNames: [String]
    public let summary: String

    public init(payload: ModelStepPayload) {
        var named: [String: String] = [:]
        var unnamed = 0
        for (key, value) in payload.fields {
            if LabAuthoredText.contains(key) {
                named[key] = LabAuthoredText.exported(value)
            } else {
                unnamed += 1
            }
        }
        fields = named
        withheldFieldCount = unnamed
        withheldValueNames = named.filter { $0.value == RecipeExport.withheldPlaceholder }.keys.sorted()
        let total = payload.fields.count
        let withheld = withheldValueNames.count + unnamed
        if withheld == 0 {
            summary = "Model step would receive \(total) field\(total == 1 ? "" : "s"), all written by Native Lab."
        } else {
            summary = "Model step would receive \(total) field\(total == 1 ? "" : "s"). \(withheld) contain\(withheld == 1 ? "s" : "") text you typed, withheld here; open Native Lab to inspect it."
        }
    }

    /// The text the intent returns: the summary, then each lab-named field.
    public var text: String {
        let lines = fields.keys.sorted().map { "\($0): \(fields[$0] ?? "")" }
        return ([summary] + lines).joined(separator: "\n")
    }
}
