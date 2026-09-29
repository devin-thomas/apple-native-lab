import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import Testing

/// Scripts are data: loaded strictly from their folder, validated whole, and never able to name
/// an actor scope, a grant, or a seed outside their folder.
@Suite struct ScriptLoadingTests {
    private func load(_ change: (inout [String: Any]) -> Void) throws -> Result<DemoScript, DemoScriptError> {
        let folder = try TemporaryFolder()
        let copy = try folder.showcaseCopy()
        try rewriteScript(in: copy, change)
        do { return .success(try DemoScript(folder: copy)) } catch { return .failure(error) }
    }

    private func steps(_ object: [String: Any]) -> [[String: Any]] {
        object["steps"] as? [[String: Any]] ?? []
    }

    @Test func theUnchangedCopyLoads() throws {
        let result = try load { _ in }
        #expect((try? result.get())?.steps.count == 11)
    }

    @Test func unknownFieldsAreRefusedAtEveryLevel() throws {
        #expect(try load { $0["actor"] = ["adapter": "app-ui"] } == .failure(.unknownField(path: "actor")))
        #expect(try load { object in
            var list = steps(object)
            list[0]["grant"] = "forever"
            object["steps"] = list
        } == .failure(.unknownField(path: "steps[0].grant")))
        #expect(try load { object in
            var list = steps(object)
            var update = list[4]["updateItem"] as! [String: Any]
            update["namespace"] = "user"
            list[4]["updateItem"] = update
            object["steps"] = list
        } == .failure(.unknownField(path: "steps[4].updateItem.namespace")))
        #expect(try load { object in
            var list = steps(object)
            list[2]["request"] = UUID().uuidString
            object["steps"] = list
        } == .failure(.unknownField(path: "steps[2].request")))
    }

    @Test func duplicateJSONKeysAreRefusedBeforeDecoding() throws {
        let folder = try TemporaryFolder()
        let copy = try folder.showcaseCopy()
        let file = copy.appending(path: "script.json")
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"dataTier\": \"public-fixture\",", with: "\"dataTier\": \"public-fixture\", \"dataTier\": \"sensitive\",")
        try text.write(to: file, atomically: false, encoding: .utf8)
        guard case .invalidJSON(.duplicateKey)? = loadFailure(copy) else {
            Issue.record("A duplicate key must be refused")
            return
        }
    }

    @Test func theSeedMustBeAnOrdinaryFileInTheScriptsFolder() throws {
        #expect(try load { $0["seed"] = "../../demo/seed.json" } == .failure(.seedFile(.invalidPath(.parentReference))))
        #expect(try load { $0["seed"] = "/etc/seed.json" } == .failure(.seedFile(.invalidPath(.absolute))))
        #expect(try load { $0["seed"] = ".seed.json" } == .failure(.seedFile(.hidden)))

        let folder = try TemporaryFolder()
        let copy = try folder.showcaseCopy()
        try FileManager.default.removeItem(at: copy.appending(path: "seed.json"))
        try FileManager.default.createSymbolicLink(
            at: copy.appending(path: "seed.json"), withDestinationURL: Showcase.atlasBasics.appending(path: "seed.json")
        )
        #expect(loadFailure(copy) == .seedFile(.symbolicLink))
    }

    @Test func aSymbolicLinkedScriptIsRefused() throws {
        let folder = try TemporaryFolder()
        let copy = try folder.showcaseCopy()
        try FileManager.default.removeItem(at: copy.appending(path: "script.json"))
        try FileManager.default.createSymbolicLink(
            at: copy.appending(path: "script.json"), withDestinationURL: Showcase.atlasBasics.appending(path: "script.json")
        )
        #expect(loadFailure(copy) == .scriptFile(.symbolicLink))
    }

    @Test func approvalsAndUndosPointTheRightWay() throws {
        // An approval must name a later perform step.
        #expect(try load { object in
            var list = steps(object)
            list[6]["approve"] = "reset"
            object["steps"] = list
        } == .failure(.invalidApproval(name("approve-archive"))))
        #expect(try load { object in
            var list = steps(object)
            list[6]["approve"] = "find-after-archive"
            object["steps"] = list
        } == .failure(.invalidApproval(name("approve-archive"))))
        // An undo must name an earlier perform step.
        #expect(try load { object in
            var list = steps(object)
            list[9]["undo"] = "undo-archive"
            object["steps"] = list
        } == .failure(.invalidUndo(name("undo-archive"))))
    }

    @Test func theFirstChangeMustBeResetDemo() throws {
        #expect(try load { object in
            var list = steps(object)
            list.remove(at: 1)
            list.remove(at: 0)
            object["steps"] = list
        } == .failure(.firstChangeMustResetDemo))
    }

    @Test func requestIDsAndStepNamesAreUnique() throws {
        #expect(try load { object in
            var list = steps(object)
            list[4]["request"] = list[1]["request"]
            object["steps"] = list
        } == .failure(.duplicateRequest(name("rename-glass"))))
        #expect(try load { object in
            var list = steps(object)
            list[3]["id"] = "list-shoreline"
            object["steps"] = list
        } == .failure(.duplicateStep(name("list-shoreline"))))
    }

    @Test func invalidValuesNameTheirField() throws {
        #expect(try load { object in
            var list = steps(object)
            var update = list[4]["updateItem"] as! [String: Any]
            update["expected"] = 0
            list[4]["updateItem"] = update
            object["steps"] = list
        } == .failure(.invalidValue(path: "steps[4].updateItem.expected")))
        #expect(try load { object in
            var list = steps(object)
            var update = list[4]["updateItem"] as! [String: Any]
            update["title"] = "Line\nbreak"
            list[4]["updateItem"] = update
            object["steps"] = list
        } == .failure(.invalidValue(path: "steps[4].updateItem.title")))
        #expect(try load { $0["dataTier"] = "public" } == .failure(.invalidValue(path: "dataTier")))
        #expect(try load { $0["subject"] = "core-9" } == .failure(.invalidSubject))
        #expect(try load { $0["formatVersion"] = 2 } == .failure(.unsupportedFormatVersion(2)))
        #expect(try load { $0["format"] = "something-else" } == .failure(.unsupportedFormat))
    }

    @Test func aStepHasExactlyOneAction() throws {
        let result = try load { object in
            var list = steps(object)
            list[2]["approve"] = "reset"
            object["steps"] = list
        }
        guard case .failure(.malformed(let path)) = result else {
            Issue.record("Two actions in one step must be refused")
            return
        }
        #expect(path.hasPrefix("steps[2]"))
    }

    @Test func aScriptCannotResetWithASeedOfItsOwnChoosing() throws {
        let seed = try smallSeed()
        let step = DemoStep(name("reset"), .perform(request: RequestID(), operation: .domain(.resetDemo(seed: seed))))
        do {
            _ = try DemoScript(
                id: name("inline-seed"), subject: "CORE-009", title: "Inline seed", dataTier: .publicFixture,
                provenance: "Test.", seed: seed, steps: [step]
            )
            Issue.record("A script must reset with its own seed only")
        } catch {
            #expect(error == .resetDemoNeedsScriptSeed(name("reset")))
        }
    }
}

private func loadFailure(_ folder: URL) -> DemoScriptError? {
    do {
        _ = try DemoScript(folder: folder)
        return nil
    } catch {
        return error
    }
}
