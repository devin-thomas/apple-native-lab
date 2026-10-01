import Foundation
import LabDomain

/// LAB-003 Shortcut Workbench: curated App Shortcuts and typed recipe walkthroughs over the same
/// authorization-checked operations Action Atlas and Portable Objects already expose.
///
/// The curated entry set is separate from the atomic action library (ADR S03). Recipes hold stable
/// entity identifiers, so renaming a source item does not break them. Sensitive changes commit only
/// through the host's `OperationService`. Shortcuts never stores secrets; recipe exports carry only text the lab wrote.
public enum ShortcutWorkbench {
    public static let experimentID = "LAB-003"
    public static let title = "Shortcut Workbench"
    public static let symbol = "hammer"

    /// Soft cap on curated App Shortcuts. The atomic Action Atlas library is not limited by this.
    public static let curatedShortcutCap = 10

    static let diagnosticSubject = DiagnosticSubject("LAB-003")
}

/// A stable recipe identifier. Distinct from item and collection IDs.
public struct RecipeID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { rawValue = UUID() }

    public var description: String { rawValue.uuidString }
}

/// A lab-owned job identity for a recipe run or export (proposed `JobHandle` companion).
public struct JobID: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { rawValue = UUID() }

    public var description: String { rawValue.uuidString }
}
