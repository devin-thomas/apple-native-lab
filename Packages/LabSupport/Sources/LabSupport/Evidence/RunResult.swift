import Foundation

/// The result of one check: exactly `passed`, `failed`, `blocked`, or `not-run`
/// (docs/TEST_STRATEGY.md).
///
/// Only `passed` counts as passing. A check that did not run, or could not run, never renders
/// or serializes as passed, and an empty set of results combines to `not-run`, not `passed`.
public enum RunResult: String, Codable, Sendable, CaseIterable {
    /// The check ran and its expected result was observed.
    case passed
    /// The check ran and its expected result was not observed.
    case failed
    /// An external prerequisite stopped the check, such as a missing device, signing capability,
    /// or toolchain. The reason says which.
    case blocked
    /// The check was not executed.
    case notRun = "not-run"

    public var title: String {
        switch self {
        case .passed: "Passed"
        case .failed: "Failed"
        case .blocked: "Blocked"
        case .notRun: "Not run"
        }
    }

    public var isPassed: Bool { self == .passed }

    /// Combines results with fixed precedence, so a combination is never more favorable than
    /// its worst member.
    ///
    /// 1. Any `failed` result makes the combination failed.
    /// 2. Otherwise any `blocked` result makes it blocked.
    /// 3. Otherwise any `not-run` result makes it not-run.
    /// 4. Otherwise, if at least one check ran and every check passed, it passed.
    /// 5. No results at all is `not-run`: nothing ran, so nothing passed.
    public static func combining(_ results: some Sequence<RunResult>) -> RunResult {
        let seen = Set(results)
        if seen.isEmpty { return .notRun }
        if seen.contains(.failed) { return .failed }
        if seen.contains(.blocked) { return .blocked }
        if seen.contains(.notRun) { return .notRun }
        return .passed
    }
}

/// A result together with what was observed, or why the check did not run.
///
/// Every case carries non-empty text. `EvidenceRecord` rejects a blank detail, and decoding
/// rejects one too, so a blocked or not-run check always says why.
public enum RunOutcome: Sendable, Equatable {
    case passed(observed: String)
    case failed(observed: String)
    case blocked(reason: String)
    case notRun(reason: String)

    public init(_ result: RunResult, detail: String) {
        switch result {
        case .passed: self = .passed(observed: detail)
        case .failed: self = .failed(observed: detail)
        case .blocked: self = .blocked(reason: detail)
        case .notRun: self = .notRun(reason: detail)
        }
    }

    public var result: RunResult {
        switch self {
        case .passed: .passed
        case .failed: .failed
        case .blocked: .blocked
        case .notRun: .notRun
        }
    }

    /// What was observed, for a check that ran, or why it did not run.
    public var detail: String {
        switch self {
        case .passed(let text), .failed(let text), .blocked(let text), .notRun(let text): text
        }
    }

    /// The result's title followed by the detail, such as "Blocked: no Watch was reachable".
    /// The result always leads, so a reader never has to infer it from the detail.
    public var summary: String { "\(result.title): \(detail)" }
}

extension RunOutcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case result
        case detail
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let result = try container.decode(RunResult.self, forKey: .result)
        let detail = try container.decode(String.self, forKey: .detail)
        guard !detail.isBlank else {
            throw DecodingError.dataCorruptedError(
                forKey: .detail, in: container,
                debugDescription: "A \(result.rawValue) outcome must say what was observed or why it did not run."
            )
        }
        self.init(result, detail: detail)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(result, forKey: .result)
        try container.encode(detail, forKey: .detail)
    }
}

extension String {
    /// Empty or whitespace only.
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
