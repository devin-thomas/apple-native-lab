import Foundation
import LabDomain
import LabStore

/// A short lowercase name for a script or step, such as `atlas-basics` or `find-glass`:
/// ASCII letters, digits, and single hyphens, 1 to 64 characters.
public struct DemoName: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public static let maximumLength = 64

    public let rawValue: String

    public init?(_ value: String) {
        guard Self.isValid(value) else { return nil }
        rawValue = value
    }

    static func isValid(_ value: String) -> Bool {
        guard (1...maximumLength).contains(value.utf8.count),
              !value.hasPrefix("-"), !value.hasSuffix("-"), !value.contains("--") else { return false }
        return value.utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let name = DemoName(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a lowercase name such as find-glass.")
        }
        self = name
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static func < (lhs: DemoName, rhs: DemoName) -> Bool { lhs.rawValue < rhs.rawValue }
}

public typealias DemoStepID = DemoName

/// One input a run depends on, identified by the SHA-256 of its exact bytes.
public struct DemoInput: Hashable, Sendable, Codable {
    /// What the input is, such as `script:atlas-basics` or `seed:atlas-basics`.
    public let name: String
    public let sha256: ContentDigest

    public init(name: String, sha256: ContentDigest) {
        self.name = name
        self.sha256 = sha256
    }

    /// The form evidence records use, such as `seed:atlas-basics@sha256:…`.
    public var reference: String { "\(name)@sha256:\(sha256.hex)" }

    private enum CodingKeys: String, CodingKey { case name, sha256 }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let hex = try container.decode(String.self, forKey: .sha256)
        guard let digest = ContentDigest(hex: hex) else {
            throw DecodingError.dataCorruptedError(forKey: .sha256, in: container, debugDescription: "Expected 64 lowercase hex digits.")
        }
        sha256 = digest
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(sha256.hex, forKey: .sha256)
    }
}

/// The change a `perform` step submits.
public enum ScriptedOperation: Hashable, Sendable {
    /// Reset Demo with the script's own seed.
    case resetDemo
    /// Any other domain operation, stated in full with its expected revision.
    case domain(DomainOperation)
    /// The undo operation recorded in an earlier step's receipt. It is read from that receipt
    /// when this step runs, never written into the script.
    case undo(of: DemoStepID)

    public var label: String {
        switch self {
        case .resetDemo: OperationKind.resetDemo.rawValue
        case .domain(let operation): operation.kind.rawValue
        case .undo: "undo"
        }
    }
}

/// A read the step performs through the service, and the items it expects, in order.
public struct ScriptedFind: Hashable, Sendable {
    public let filter: ItemFilter
    public let expected: [ItemID]

    public init(filter: ItemFilter, expected: [ItemID]) {
        self.filter = filter
        self.expected = expected
    }
}

/// What one step does.
public enum DemoAction: Hashable, Sendable {
    /// The person's explicit approval of one later `perform` step. The runner asks the grant
    /// ledger for a grant covering exactly that step's operation, as a host does when a person
    /// confirms. It is the only way a script obtains a grant.
    case approve(DemoStepID)
    /// Submits one operation through `OperationService` under the step's request ID.
    case perform(request: RequestID, operation: ScriptedOperation)
    /// Reads items through `OperationService.findItems` and compares their IDs with `expected`.
    case find(ScriptedFind)

    public var kind: String {
        switch self {
        case .approve: "approve"
        case .perform: "perform"
        case .find: "find"
        }
    }
}

public struct DemoStep: Hashable, Sendable {
    public let id: DemoStepID
    public let action: DemoAction
    /// A sentence for the reader, such as "Rename the sea glass sample."
    public let description: String

    public init(_ id: DemoStepID, _ action: DemoAction, description: String? = nil) {
        self.id = id
        self.action = action
        self.description = description.flatMap { $0.isBlank ? nil : $0 } ?? Self.describe(action)
    }

    private static func describe(_ action: DemoAction) -> String {
        switch action {
        case .approve(let step): "Approve step \(step)."
        case .perform(let request, let operation):
            switch operation {
            case .undo(let step): "Undo step \(step) (request \(request))."
            default: "Perform \(operation.label) (request \(request))."
            }
        case .find(let find): "Find items; expect \(find.expected.count)."
        }
    }
}

/// A replayable demonstration: a seed and a declared list of steps.
///
/// Every run starts from a fresh, empty store, and the script's first `perform` step must be
/// Reset Demo, so each replay begins from the seed and nothing else. A script is validated whole
/// when it is created or loaded: unique step names and request IDs, an approval only for a later
/// `perform` step, and an undo only of an earlier one.
public struct DemoScript: Hashable, Sendable {
    public static let maximumSteps = 200

    public let id: DemoName
    /// The ticket or experiment the demonstration is evidence for, such as `CORE-009`.
    public let subject: String
    public let title: String
    /// The rights class of the script and seed. A showcase fixture is `public-fixture`.
    public let dataTier: DataTier
    /// Where the content comes from and its license.
    public let provenance: String
    public let seed: DemoSeed
    public let steps: [DemoStep]
    /// Areas this demonstration does not exercise, carried into every run and export.
    public let untested: [String]
    /// The exact inputs, with hashes: the script and the seed.
    public let inputs: [DemoInput]

    /// Creates a script in code. Its inputs are hashed from the canonical encoding of the steps
    /// and the seed.
    public init(
        id: DemoName,
        subject: String,
        title: String,
        dataTier: DataTier,
        provenance: String,
        seed: DemoSeed,
        steps: [DemoStep],
        untested: [String] = []
    ) throws(DemoScriptError) {
        let seedDigest: ContentDigest
        let stepsDigest: ContentDigest
        do {
            seedDigest = try Canonical.digest(seed)
            stepsDigest = try Canonical.digest(CanonicalSteps(id: id, subject: subject, steps: steps))
        } catch {
            throw .malformed(path: "steps")
        }
        try self.init(
            id: id, subject: subject, title: title, dataTier: dataTier, provenance: provenance, seed: seed, steps: steps,
            untested: untested,
            inputs: [
                DemoInput(name: "script:\(id)", sha256: stepsDigest),
                DemoInput(name: "seed:\(id)", sha256: seedDigest),
            ]
        )
    }

    init(
        id: DemoName,
        subject: String,
        title: String,
        dataTier: DataTier,
        provenance: String,
        seed: DemoSeed,
        steps: [DemoStep],
        untested: [String],
        inputs: [DemoInput]
    ) throws(DemoScriptError) {
        guard DiagnosticSubject(subject) != nil else { throw .invalidSubject }
        guard !title.isBlank else { throw .blankField("title") }
        guard !provenance.isBlank else { throw .blankField("provenance") }
        guard !untested.contains(where: \.isBlank) else { throw .blankField("untested") }
        try Self.validate(steps)
        self.id = id
        self.subject = subject
        self.title = title
        self.dataTier = dataTier
        self.provenance = provenance
        self.seed = seed
        self.steps = steps
        self.untested = untested
        self.inputs = inputs
    }

    /// The digest that names this script's inputs together. Replays of the same inputs share it.
    public var inputDigest: ContentDigest {
        let joined = inputs.map(\.reference).joined(separator: "\n")
        return ContentDigest.sha256(Data(joined.utf8))
    }

    private static func validate(_ steps: [DemoStep]) throws(DemoScriptError) {
        guard !steps.isEmpty else { throw .noSteps }
        guard steps.count <= maximumSteps else { throw .tooManySteps(limit: maximumSteps) }
        var positions: [DemoStepID: Int] = [:]
        var requests = Set<RequestID>()
        for (index, step) in steps.enumerated() {
            guard positions.updateValue(index, forKey: step.id) == nil else { throw .duplicateStep(step.id) }
            if case .perform(let request, let operation) = step.action {
                guard requests.insert(request).inserted else { throw .duplicateRequest(step.id) }
                if case .domain(.resetDemo) = operation { throw .resetDemoNeedsScriptSeed(step.id) }
            }
        }
        guard let firstPerform = steps.first(where: { if case .perform = $0.action { true } else { false } }),
              case .perform(_, .resetDemo) = firstPerform.action else {
            throw .firstChangeMustResetDemo
        }
        for (index, step) in steps.enumerated() {
            switch step.action {
            case .approve(let target):
                guard let position = positions[target], position > index,
                      case .perform = steps[position].action else { throw .invalidApproval(step.id) }
            case .perform(_, .undo(let target)):
                guard let position = positions[target], position < index,
                      case .perform = steps[position].action else { throw .invalidUndo(step.id) }
            case .perform, .find:
                break
            }
        }
    }
}

/// The part of a code-built script that its hash covers besides the seed.
private struct CanonicalSteps: Encodable {
    let id: DemoName
    let subject: String
    let steps: [DemoStep]
}

extension DemoStep: Encodable {
    private enum CodingKeys: String, CodingKey { case id, kind, description, request, operation, approves, undoes, find }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(action.kind, forKey: .kind)
        try container.encode(description, forKey: .description)
        switch action {
        case .approve(let target):
            try container.encode(target, forKey: .approves)
        case .perform(let request, let operation):
            try container.encode(request, forKey: .request)
            switch operation {
            case .resetDemo: try container.encode(OperationKind.resetDemo.rawValue, forKey: .operation)
            case .domain(let operation): try container.encode(operation, forKey: .operation)
            case .undo(let target): try container.encode(target, forKey: .undoes)
            }
        case .find(let find):
            try container.encode(FindEncoding(find), forKey: .find)
        }
    }
}

struct FindEncoding: Encodable {
    let collection: CollectionID?
    let text: String?
    let includeArchived: Bool
    let limit: Int
    let expect: [ItemID]

    init(_ find: ScriptedFind) {
        collection = find.filter.collectionID
        text = find.filter.text
        includeArchived = find.filter.includeArchived
        limit = find.filter.limit
        expect = find.expected
    }
}
