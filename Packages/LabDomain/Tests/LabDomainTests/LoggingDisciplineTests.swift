import Foundation
import Testing

/// CORE-006: lab code logs only through the diagnostics facade.
///
/// Every Swift source file in the hosts and packages is searched for a direct logging or console
/// API. The only exception is the facade's own folder, `LabDomain/Diagnostics`, where the system
/// log sink lives. Tests are not searched: they run in the developer's terminal, not in the app.
@Suite struct LoggingDisciplineTests {
    private static let forbidden: [(name: String, pattern: String)] = [
        ("print", #"(?<![\w.])print\("#),
        ("debugPrint", #"(?<![\w.])debugPrint\("#),
        ("dump", #"(?<![\w.])dump\("#),
        ("NSLog", #"\bNSLog\("#),
        ("os_log", #"\bos_log\("#),
        ("os_signpost", #"\bos_signpost\("#),
        ("Logger", #"\bLogger\("#),
        ("import os", #"(?m)^\s*import\s+(os|OSLog)\b"#),
        ("standard streams", #"FileHandle\.standard(Error|Output)"#),
        ("C streams", #"\b(f?puts|fprintf|printf)\("#),
    ]

    private static func matches(_ pattern: String, _ text: String) throws -> Bool {
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let allowedFolder = "Packages/LabDomain/Sources/LabDomain/Diagnostics/"

    private func sourceFiles() throws -> [(path: String, text: String)] {
        let root = HostileFixtures.repositoryRoot
        var files: [(String, String)] = []
        for top in ["Apps", "Packages", "Extensions"] {
            let folder = root.appending(path: top)
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let path = String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(root.standardizedFileURL.path(percentEncoded: false).count))
                let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
                let components = relative.split(separator: "/")
                if components.contains(where: { $0 == ".build" || $0 == "Tests" || $0 == ".swiftpm" }) { continue }
                if top == "Packages", components.count > 2, components[2] != "Sources" { continue }
                files.append((relative, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return files
    }

    @Test func labCodeLogsOnlyThroughTheDiagnosticsFacade() throws {
        let files = try sourceFiles()
        #expect(files.count > 40, "the search must see the sources")
        #expect(files.contains { $0.path.hasPrefix(Self.allowedFolder) })
        var violations: [String] = []
        for file in files where !file.path.hasPrefix(Self.allowedFolder) {
            for rule in Self.forbidden {
                for (number, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                    if try Self.matches(rule.pattern, String(code)) { violations.append("\(file.path):\(number + 1) uses \(rule.name)") }
                }
            }
        }
        #expect(violations.isEmpty, "Use DiagnosticsLog instead:\n\(violations.joined(separator: "\n"))")
    }

    @Test func theSearchCatchesEachForbiddenCall() throws {
        let samples = [
            "print(title)", "debugPrint(x)", "dump(record)", "NSLog(\"%@\", name)", "os_log(\"%{public}@\", path)",
            "os_signpost(.begin, log: log, name: \"x\")", "let log = Logger(subsystem: s, category: c)", "import OSLog",
            "  import os", "FileHandle.standardError.write(data)", "fputs(text, stderr)",
        ]
        for sample in samples {
            let caught = try Self.forbidden.contains { try Self.matches($0.pattern, sample) }
            #expect(caught, "\(sample)")
        }
        for allowed in ["log.record(\"import.stage\", outcome: .succeeded)", "blueprint(x)", "self.print(x)", "sprint(1)"] {
            let caught = try Self.forbidden.contains { try Self.matches($0.pattern, allowed) }
            #expect(!caught, "\(allowed)")
        }
    }
}
