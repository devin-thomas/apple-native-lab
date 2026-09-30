@testable import AccessSuperpower
import Foundation
import LabDomain
import Testing

/// LAB-035-B step 1: the showcase script that `Packages/LabDemo` replays as evidence
/// (`Fixtures/showcase/access-superpower/`), run here through the AccessSuperpower module from a
/// clean store. The script states every operation in full; this test checks that the module
/// builds exactly those operations (Set Up Practice, the task's restore, the miss, and Reset
/// Practice), that its judgment and chart read as the chart fixture says at each point, and that
/// the script asks for the person's approval exactly where the hosts need a grant.
///
/// LabFeatures does not depend on LabDemo, so the script is read as plain JSON. A step kind this
/// file does not map fails the test rather than being skipped. Fixture path: an in-memory store
/// behind `OperationService` with `GrantAuthorizationPolicy`.
@Suite struct AccessSuperpowerShowcaseReplayTests {
    @Test func theShowcaseSeedIsTheDemoSeedTheModuleIsTestedWith() throws {
        let showcase = try Data(contentsOf: AccessShowcaseFile.folder.appending(path: "seed.json"))
        let demo = try Data(contentsOf: Fixtures.root.appending(path: "demo/seed.json"))
        #expect(showcase == demo)
    }

    /// Every step that needs a grant from the app UI is approved just before it, and nothing else is.
    @Test func theScriptApprovesExactlyTheChangesThatNeedAGrant() throws {
        let file = try AccessShowcaseFile.load()
        let approved = Set(file.steps.compactMap { if case .approve(let target) = $0.action { target } else { nil } })
        var needsGrant = Set<String>()
        for step in file.steps {
            if let kind = step.action.kind, GrantRequirement.sensitiveCommits.requiresGrant(kind, from: .appUI) {
                needsGrant.insert(step.id)
            }
        }
        #expect(approved == needsGrant)
        #expect(needsGrant.count == 10, "reset, 6 practice archives, the undo, and the person's two archives")
    }

    @Test func theModuleBuildsTheScriptsOperationsAndJudgesTheTaskAsTheFixtureReads() async throws {
        let file = try AccessShowcaseFile.load()
        let fixture = try Fixtures.chart()
        let lab = try await TestLab.seeded()
        var receipts: [String: ActionReceipt] = [:]
        var outcome: TaskOutcome?
        var checked = Set<String>()

        /// The script's operations for every step whose ID starts with `prefix`, in order.
        func operations(_ prefix: String) -> [DomainOperation] {
            file.steps.filter { $0.id.hasPrefix(prefix) }.compactMap(\.action.operation)
        }

        for step in file.steps {
            let tally = try await lab.tally()
            switch step.action {
            case .approve:
                continue // TestLab issues the grant at the commit, as a control press does.
            case .resetDemo:
                continue // TestLab.seeded() committed Reset Demo with the same seed.
            case .find(let collection, let includeArchived, let expected):
                let filter = try ItemFilter(collectionID: collection, includeArchived: includeArchived, limit: ItemFilter.allowedLimits.upperBound)
                let found = try await lab.service.findItems(filter, as: TestLab.appUI).map(\.id)
                #expect(found == expected, "\(step.id)")
                // A demo collection's find is the table's row for that bar.
                if let shown = tally.collections.first(where: { $0.id == collection }) {
                    let table = shown.samples.filter { includeArchived || !$0.isArchived }.map(\.id)
                    #expect(table == expected, "\(step.id): the table the chart and list read from")
                }
            case .undo(let earlier):
                let undo = try #require(receipts[earlier]?.undo, "\(step.id)")
                receipts[step.id] = try await lab.perform(undo)
                if outcome != nil { #expect(AccessibleTask.status(of: try await lab.tally(), after: nil) == .toDo) }
                outcome = nil
            case .change(let operation):
                if step.id == "practice-quartz" {
                    #expect(AccessibleTask.status(of: tally, after: nil) == .nothingArchived)
                    #expect(PracticeSet.standard.setUpOperations(in: tally) == operations("practice-"), "Set Up Practice")
                    checked.insert("set-up")
                }
                if step.id == "reset-practice-quartz" {
                    #expect(PracticeSet.standard.resetOperations(in: tally) == operations("reset-practice-"), "Reset Practice")
                    checked.insert("reset")
                }
                if step.id == "restore-quartz" || step.id == "restore-vellum" {
                    // The chart the person reads just before the restore is the fixture's.
                    #expect(ChartSemantics(tally: tally) == fixture.chart, "\(step.id)")
                    let finishes = step.id == "restore-quartz"
                    let expected = finishes ? fixture.task.finish : fixture.task.miss
                    #expect(operation.target == .item(ItemID(expected.restore)))
                    #expect(try AccessibleTask.restoreOperation(for: ItemID(expected.restore), in: tally) == operation, "\(step.id)")
                    let judged = try #require(AccessibleTask.judge(restoring: ItemID(expected.restore), in: tally))
                    #expect(judged.completesTask == finishes)
                    #expect(judged.sentence == expected.outcome)
                    outcome = judged
                    checked.insert(step.id)
                }
                let receipt = try await lab.perform(operation, requestID: step.request ?? RequestID())
                #expect(receipt.conflict == nil, "\(step.id)")
                #expect(receipt.admitted.adapter == .appUI)
                receipts[step.id] = receipt
                if step.id == "restore-quartz" || step.id == "restore-vellum" {
                    let after = try await lab.tally()
                    let expected = step.id == "restore-quartz" ? fixture.task.finish : fixture.task.miss
                    #expect(ChartSemantics.summary(of: after) == expected.summaryAfter, "\(step.id)")
                    #expect(AccessibleTask.status(of: after, after: outcome) == (step.id == "restore-quartz" ? .done : .toDo))
                }
            }
        }
        #expect(checked == ["set-up", "reset", "restore-quartz", "restore-vellum"])

        // The person's collection and item never entered the task, and stayed archived.
        let tally = try await lab.tally()
        #expect(tally.collections.count == 3 && tally.totalArchived == 1, "only Amber swatch, which is not a practice sample")
        #expect(PracticeSet.standard.resetOperations(in: tally).isEmpty)
        #expect(AccessibleTask.status(of: tally, after: nil) == .toDo)
    }
}

// MARK: - The showcase file

/// `Fixtures/showcase/access-superpower/`, decoded into the steps this file can replay.
struct AccessShowcaseFile {
    static let folder = Fixtures.root.appending(path: "showcase/access-superpower", directoryHint: .isDirectory)

    enum Action {
        case approve(String)
        case resetDemo
        case change(DomainOperation)
        case undo(String)
        case find(collection: CollectionID?, includeArchived: Bool, expected: [ItemID])

        var operation: DomainOperation? {
            if case .change(let operation) = self { operation } else { nil }
        }

        /// The kind of change the step submits, when it is one. An undo here always archives.
        var kind: OperationKind? {
            switch self {
            case .change(let operation): operation.kind
            case .resetDemo: .resetDemo
            case .undo: .archiveItem
            case .approve, .find: nil
            }
        }
    }

    struct Step {
        let id: String
        let request: RequestID?
        let action: Action
    }

    let steps: [Step]

    static func load() throws -> AccessShowcaseFile {
        let data = try Data(contentsOf: folder.appending(path: "script.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["subject"] as? String == "LAB-035")
        let raw = try #require(object["steps"] as? [[String: Any]])
        return AccessShowcaseFile(steps: try raw.map(step))
    }

    private static func step(_ raw: [String: Any]) throws -> Step {
        let id = try #require(raw["id"] as? String)
        let request = (raw["request"] as? String).flatMap(UUID.init(uuidString:)).map(RequestID.init(rawValue:))
        func uuid(_ value: Any?) throws -> UUID { try #require((value as? String).flatMap(UUID.init(uuidString:)), "\(id)") }
        func entry(_ key: String) -> [String: Any]? { raw[key] as? [String: Any] }

        let action: Action
        if let target = raw["approve"] as? String {
            action = .approve(target)
        } else if entry("resetDemo") != nil {
            action = .resetDemo
        } else if let target = raw["undo"] as? String {
            action = .undo(target)
        } else if let find = entry("find") {
            action = .find(
                collection: try (find["collection"]).map(uuid).map(CollectionID.init(rawValue:)),
                includeArchived: find["includeArchived"] as? Bool ?? false,
                expected: try (find["expect"] as? [Any] ?? []).map { ItemID(rawValue: try uuid($0)) }
            )
        } else if let archive = entry("archiveItem") {
            action = .change(.archiveItem(id: ItemID(rawValue: try uuid(archive["id"])), expected: try revision(archive, id)))
        } else if let restore = entry("restoreItem") {
            action = .change(.restoreItem(id: ItemID(rawValue: try uuid(restore["id"])), expected: try revision(restore, id)))
        } else if let collection = entry("createCollection") {
            action = .change(.createCollection(draft: CollectionDraft(
                id: CollectionID(rawValue: try uuid(collection["id"])), title: try EntityTitle(try #require(collection["title"] as? String))
            )))
        } else if let item = entry("createItem") {
            action = .change(.createItem(draft: ItemDraft(
                id: ItemID(rawValue: try uuid(item["id"])),
                in: CollectionID(rawValue: try uuid(item["collection"])),
                title: try EntityTitle(try #require(item["title"] as? String)),
                note: try ItemNote(item["note"] as? String ?? "")
            )))
        } else {
            Issue.record("step \(id) has a kind this replay does not map")
            throw CancellationError()
        }
        return Step(id: id, request: request, action: action)
    }

    private static func revision(_ entry: [String: Any], _ id: String) throws -> Revision {
        try #require((entry["expected"] as? Int).flatMap(Revision.init(rawValue:)), "\(id)")
    }
}
