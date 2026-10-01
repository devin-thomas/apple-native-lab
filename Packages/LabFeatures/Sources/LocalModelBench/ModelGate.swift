/// Which license this build will load. Only the fixture license is accepted. Anything else is
/// refused before a loader runs, including a model whose license text is merely present.
public enum ModelLicense: Hashable, Sendable, Codable {
    /// The lab's own fixture executor. It is not a downloaded model.
    case fixture
    /// A license this build has not accepted.
    case unreviewed(String)

    public var label: String {
        switch self {
        case .fixture: "fixture"
        case .unreviewed(let text): text
        }
    }
}

/// A model the bench might load. The memory figure is the caller's budget for it, checked
/// before any loader runs. This type does not allocate that many bytes.
public struct ModelDescriptor: Hashable, Sendable, Codable {
    public let id: String
    public let license: ModelLicense
    /// Bytes the model would need. Zero is refused: a missing budget is not a small model.
    public let declaredMemoryBytes: UInt64

    public init(id: String, license: ModelLicense, declaredMemoryBytes: UInt64) throws(BenchError) {
        guard !id.isEmpty, id.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            throw .invalidCase
        }
        if case .unreviewed(let text) = license {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .licenseRefused }
        }
        guard declaredMemoryBytes > 0 else { throw .missingMemoryBudget }
        self.id = id
        self.license = license
        self.declaredMemoryBytes = declaredMemoryBytes
    }

    /// The fixture model: 1 MiB declared, fixture license, nothing allocated by naming it.
    public static let fixture = ModelDescriptor(
        unchecked: "lab-015-fixture", license: .fixture, declaredMemoryBytes: 1_048_576
    )

    init(unchecked id: String, license: ModelLicense, declaredMemoryBytes: UInt64) {
        self.id = id
        self.license = license
        self.declaredMemoryBytes = declaredMemoryBytes
    }
}

/// Proof that `ModelGate.admit` allowed a load. A loader takes one of these and nothing else,
/// so a refused model never reaches it.
public struct LoadAdmission: Sendable, Hashable {
    public let modelID: String
    public let declaredMemoryBytes: UInt64
    public let availableBytes: UInt64

    init(model: ModelDescriptor, availableBytes: UInt64) {
        modelID = model.id
        declaredMemoryBytes = model.declaredMemoryBytes
        self.availableBytes = availableBytes
    }
}

/// What a loader returns after admission. The fixture loader reports zero bytes allocated.
public struct LoadedModel: Sendable, Hashable {
    public let allocatedBytes: UInt64
    /// Always false for the fixture loader.
    public let inference: Bool

    public init(allocatedBytes: UInt64, inference: Bool) {
        self.allocatedBytes = allocatedBytes
        self.inference = inference
    }
}

/// License, then memory. Both happen before a loader is called, and this type allocates nothing
/// of `declaredMemoryBytes`.
public enum ModelGate {
    public static func admit(_ model: ModelDescriptor, availableBytes: UInt64) throws(BenchError) -> LoadAdmission {
        guard case .fixture = model.license else { throw .licenseRefused }
        guard model.declaredMemoryBytes <= availableBytes else {
            throw .exceedsMemory(required: model.declaredMemoryBytes, available: availableBytes)
        }
        return LoadAdmission(model: model, availableBytes: availableBytes)
    }
}
