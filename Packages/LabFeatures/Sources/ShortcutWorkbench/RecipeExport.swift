import Foundation
import LabDomain

/// A recipe export document. Secret-shaped fields are always redacted before encoding.
///
/// ```json
/// {
///   "format": "native-lab-recipe",
///   "formatVersion": 1,
///   "id": "<UUID>",
///   "title": "…",
///   "steps": […],
///   "sourceItemIDs": ["<UUID>", …],
///   "modelStep": { "fields": { "prompt": "…", "apiKey": "[redacted]" } }
/// }
/// ```
public struct RecipeExport: Hashable, Sendable {
    public let recipe: RecipeDefinition
    public let data: Data
    public let filename: String
    /// Keys that were present and redacted. Never the raw values.
    public let redactedKeys: [String]

    public init(recipe: RecipeDefinition) {
        var copy = recipe
        var redacted: [String] = []
        if let model = copy.modelStep {
            let before = model.fields
            let after = SecretRedaction.redact(before)
            redacted = before.keys.filter { SecretRedaction.isSecretField($0) }.sorted()
            copy.modelStep = ModelStepPayload(fields: after)
        }
        // Defensive: never encode a raw secret even if a caller mutated elsewhere.
        self.recipe = copy
        self.redactedKeys = redacted
        self.data = Self.encode(copy)
        self.filename = "\(Self.safeName(copy.title)).recipe.json"
    }

    /// Whether the encoded UTF-8 text contains any of the original secret values.
    public func containsRawSecret(_ secrets: [String]) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        return secrets.contains { !$0.isEmpty && text.contains($0) }
    }

    public var text: String { String(decoding: data, as: UTF8.self) }

    private static func encode(_ recipe: RecipeDefinition) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(ExportDocument(recipe))) ?? Data()
    }

    private static func safeName(_ title: String) -> String {
        let replaced = title.map { "/:\\".contains($0) ? Character("-") : $0 }
        var name = String(replaced).trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        if name.count > 60 { name = String(name.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "Lab recipe" : name
    }
}

/// Wire shape for a recipe export. Keeps `format` / `formatVersion` beside the definition fields.
private struct ExportDocument: Encodable {
    let format: String
    let formatVersion: Int
    let id: UUID
    let title: String
    let steps: [StepWire]
    let sourceItemIDs: [UUID]
    let modelStep: ModelWire?

    init(_ recipe: RecipeDefinition) {
        format = RecipeDefinition.format
        formatVersion = RecipeDefinition.formatVersion
        id = recipe.id.rawValue
        title = recipe.title
        steps = recipe.steps.map(StepWire.init)
        sourceItemIDs = recipe.sourceItemIDs.map(\.rawValue)
        modelStep = recipe.modelStep.map { ModelWire(fields: $0.fields) }
    }

    struct StepWire: Encodable {
        let order: Int
        let kind: String
        let detail: String?

        init(_ step: RecipeStep) {
            order = step.order
            kind = step.kind.rawValue
            detail = step.detail
        }
    }

    struct ModelWire: Encodable {
        let fields: [String: String]
    }
}

/// What an optional model step would receive, after redaction.
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
