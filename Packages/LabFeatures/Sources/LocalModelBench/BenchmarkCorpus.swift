import Foundation
import LabDomain

/// One task in the original fixed corpus. The prompt is the input; `expected` is the only
/// accepted answer. The fixture executor does not infer it.
public struct BenchmarkCase: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let prompt: String
    public let expected: String

    public init(id: String, prompt: String, expected: String) throws(BenchError) {
        try Self.validate(id)
        try Self.validate(prompt)
        try Self.validate(expected)
        self.id = id
        self.prompt = prompt
        self.expected = expected
    }

    init(unchecked id: String, prompt: String, expected: String) {
        self.id = id
        self.prompt = prompt
        self.expected = expected
    }

    private static func validate(_ text: String) throws(BenchError) {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            throw .invalidCase
        }
    }
}

/// The corpus this build benchmarks. It is original and fixed: four short tasks, no downloaded text.
public enum EvaluationCorpus {
    public static let id = "lab-015-fixture-v1"

    public static let cases: [BenchmarkCase] = [
        BenchmarkCase(unchecked: "slate-token", prompt: "Repeat the token SLATE.", expected: "SLATE"),
        BenchmarkCase(unchecked: "kestrel-count", prompt: "How many characters are in kestrel?", expected: "7"),
        BenchmarkCase(unchecked: "sum-nineteen", prompt: "Add 19 and 23.", expected: "42"),
        BenchmarkCase(unchecked: "reverse-maple", prompt: "Reverse the token MAPLE.", expected: "ELPAM"),
    ]

    /// SHA-256 of the canonical case list. A changed corpus changes every export.
    public static func digest() -> ContentDigest {
        ContentDigest.sha256(canonicalCases())
    }

    static func canonicalCases() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(cases)) ?? Data()
    }
}
