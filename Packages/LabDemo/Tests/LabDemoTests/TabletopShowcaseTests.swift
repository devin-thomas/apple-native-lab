import CryptoKit
import Foundation
@testable import LabDemo
import LabDomain
import LabStore
import LabSupport
import Testing

/// `Fixtures/showcase/tabletop-reality/`: LAB-023's fixture interaction, replayed from a clean store.
enum TabletopShowcase {
    static let folder = Showcase.fixtures.appending(path: "tabletop-reality", directoryHint: .isDirectory)
    /// The seed the app bundles and seeds its first run with.
    static let appSeed = Showcase.repositoryRoot.appending(path: "Fixtures/demo/seed.json")
    /// The kit the tabletop places objects from.
    static let kit = Showcase.repositoryRoot.appending(path: "Packages/LabFeatures/Sources/TabletopReality/Resources/tabletop-kit.json")

    static let windmill = anchor("F696EB2C-1CC9-4EC4-855E-7E97E4B14A6A")
    static let cottage = anchor("21F89892-82C8-4C06-BF85-304AEBAA21C0")
    static let pine = anchor("30DB25CF-F70B-4037-8BB2-0A7D84C9418D")
    static let lantern = anchor("92EF6094-D878-49C7-BBA0-D15A0E4FE3AD")
    static let lighthouse = anchor("7230CBE0-E5B2-4D8A-A9BA-60DB5057C28C")
    static let lanternAfterReset = anchor("306AB1A4-686C-441E-A6BA-DC09DD1E645D")
    static let fieldNotes = CollectionID(rawValue: UUID(uuidString: "FCE4BCC5-5370-4698-A674-1E01E2D48781")!)
    static let sketch = ItemID(rawValue: UUID(uuidString: "81A31255-35F6-4969-AAB8-CD8864215172")!)

    static func anchor(_ text: String) -> AnchorID { AnchorID(rawValue: UUID(uuidString: text)!) }

    static func script() throws -> DemoScript {
        try DemoScript(folder: folder)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    /// A copy of the showcase folder with its script changed, for tests that need a variant.
    static func variant(in temporary: TemporaryFolder, _ change: (inout [String: Any]) -> Void) throws -> URL {
        let copy = temporary.url.appending(path: "tabletop-reality", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        try rewriteScript(in: copy, change)
        return copy
    }

    static func receipt(_ run: DemoRun, _ step: String) -> ActionReceipt? {
        run.steps.first { $0.id == name(step) }?.receipt
    }

    static func pose(_ x: Int, _ z: Int, yaw: Int = 0) -> AnchorPose { try! AnchorPose(x: x, z: z, yaw: yaw) }
}

/// LAB-023-B step 1: replay the complete fixture interaction from a clean state. Fixture path: the
/// replay proves the domain contract the virtual table and the live adapter both call, not
/// RealityKit, ARKit, a camera, a view, or a device.
@Suite struct TabletopShowcaseTests {
    @Test func theShowcaseSeedIsTheAppsDemoSeedByteForByte() throws {
        #expect(try TabletopShowcase.data("seed.json") == (try Data(contentsOf: TabletopShowcase.appSeed)))
    }

    @Test func theShowcaseLoadsWithTheHashesOfItsExactBytes() throws {
        let script = try TabletopShowcase.script()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        #expect(script.subject == "LAB-023")
        #expect(script.dataTier == .publicFixture)
        #expect(script.steps.count == 19)
        #expect(script.inputs.map(\.reference) == [
            "script:tabletop-reality@sha256:\(hex(try TabletopShowcase.data("script.json")))",
            "seed:tabletop-reality@sha256:\(hex(try Data(contentsOf: TabletopShowcase.appSeed)))",
        ])
        let turn = try #require(script.steps.first { $0.id == name("turn-lighthouse") })
        #expect(turn.action == .perform(
            request: RequestID(rawValue: UUID(uuidString: "DA226012-54F0-4C67-8CE2-902B6D2044C5")!),
            operation: .domain(.moveAnchor(id: TabletopShowcase.lighthouse, expected: revision(2), pose: TabletopShowcase.pose(280, -200, yaw: 15)))
        ))
    }

    /// The first four placements are the kit's starter scene, in its order, at its poses, with its
    /// titles: what Set Out Starter Scene commits on an empty table.
    @Test func theFirstPlacementsAreTheKitsStarterScene() throws {
        let kit = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: TabletopShowcase.kit)) as? [String: Any])
        let fixtures = try #require(kit["fixtures"] as? [[String: Any]])
        let titles = Dictionary(uniqueKeysWithValues: fixtures.map { ($0["key"] as! String, $0["title"] as! String) })
        let starter = try #require(kit["starter"] as? [[String: Any]])
        let placements = try TabletopShowcase.script().steps.compactMap { step -> AnchorDraft? in
            if case .perform(_, .domain(.placeAnchor(let draft))) = step.action { draft } else { nil }
        }
        #expect(placements.count == 6)
        for (draft, expected) in zip(placements.prefix(4), starter) {
            #expect(draft.fixture.value == expected["fixture"] as? String)
            #expect(draft.title.value == titles[draft.fixture.value])
            #expect(draft.pose == TabletopShowcase.pose(expected["x"] as! Int, expected["z"] as! Int, yaw: expected["yaw"] as! Int))
        }
        #expect(placements.allSatisfy { titles[$0.fixture.value] == $0.title.value }, "every object is one the kit draws")
    }

    @Test func theInteractionPassesFromACleanStoreAndResetRemovesOnlyTheAnchors() async throws {
        let run = await DemoRunner(store: .temporarySQLite).run(try TabletopShowcase.script())
        checkStepInvariants(run)
        #expect(run.result == .passed, "\(run.outcome.summary)")
        #expect(run.steps.count == 19)

        let state = try #require(run.finalState)
        #expect(state.anchors == [LabAnchor(
            id: TabletopShowcase.lanternAfterReset, fixture: try FixtureKey("lantern"), title: "Lantern", pose: TabletopShowcase.pose(0, 0)
        )])
        #expect(state.collections.count == 4 && state.items.count == 13)
        let yours = try #require(state.items.first { $0.id == TabletopShowcase.sketch })
        #expect(yours.namespace == .user && yours.revision == .initial && yours.collectionID == TabletopShowcase.fieldNotes)
        #expect(state.items.filter { $0.namespace == .demo }.allSatisfy { $0.revision == .initial && !$0.isArchived },
                "nothing on the table touched a sample")

        // Place, move, and turn name their object and offer their undo.
        let lighthouse = EntityReference.anchor(TabletopShowcase.lighthouse)
        let placed = try #require(TabletopShowcase.receipt(run, "place-lighthouse"))
        #expect(placed.summary == "Placed “Lighthouse”.")
        #expect(placed.changes.map(\.entity) == [lighthouse] && placed.changes.map(\.previousRevision) == [nil])
        #expect(placed.undo == .removeAnchor(id: TabletopShowcase.lighthouse, expected: .initial))
        let moved = try #require(TabletopShowcase.receipt(run, "move-lighthouse"))
        #expect(moved.summary == "Moved “Lighthouse”.")
        #expect(moved.undo == .moveAnchor(id: TabletopShowcase.lighthouse, expected: revision(2), pose: TabletopShowcase.pose(300, -200)))
        let turned = try #require(TabletopShowcase.receipt(run, "turn-lighthouse"))
        #expect(turned.summary == "Turned “Lighthouse”.")
        #expect(turned.changes.map(\.newRevision) == [revision(3)])

        // The removal deleted the anchor; its undo placed the same anchor at the same pose.
        let removed = try #require(TabletopShowcase.receipt(run, "remove-lighthouse"))
        #expect(removed.removed == [lighthouse] && removed.changes.isEmpty)
        #expect(removed.undo == .placeAnchor(draft: AnchorDraft(
            id: TabletopShowcase.lighthouse, fixture: try FixtureKey("lighthouse"), title: "Lighthouse", pose: TabletopShowcase.pose(280, -200, yaw: 15)
        )))
        let restored = try #require(TabletopShowcase.receipt(run, "undo-remove-lighthouse"))
        #expect(restored.admitted.operation == removed.undo)
        #expect(restored.changes.map(\.entity) == [lighthouse] && restored.changes.map(\.newRevision) == [.initial])

        // The second Reset Demo removed exactly the five anchors and changed nothing else.
        let reset = try #require(TabletopShowcase.receipt(run, "reset-again"))
        #expect(Set(reset.removed) == Set([
            TabletopShowcase.windmill, TabletopShowcase.cottage, TabletopShowcase.pine, TabletopShowcase.lantern, TabletopShowcase.lighthouse,
        ].map(EntityReference.anchor)))
        #expect(reset.removed.count == 5 && reset.removed.allSatisfy { $0.kind == .anchor })
        #expect(reset.changes.isEmpty && reset.undo == nil)
        #expect(reset.summary == "Reset the demo to its original 3 collections and 12 items: cleared 5 placed objects.")

        // Only the removal and the two resets asked for approval; every receipt is the app UI's.
        #expect(run.steps.compactMap(\.approval).map(\.operation) == [.resetDemo, .removeAnchor, .resetDemo])
        let anchorReceipts = run.steps.compactMap(\.receipt).filter { $0.affectedEntities.contains { $0.kind == .anchor } }
        #expect(anchorReceipts.count == 11)
        #expect(run.steps.compactMap(\.receipt).allSatisfy { $0.status == .committed && $0.admitted.adapter == .appUI })
    }

    @Test func replaysShareOneFingerprintAcrossRunsAndStores() async throws {
        let script = try TabletopShowcase.script()
        let first = await DemoRunner(store: .temporarySQLite).run(script)
        let second = await DemoRunner(store: .temporarySQLite, clock: SuspendingIntervalClock()).run(script)
        let inMemory = await DemoRunner.manual().run(script)
        #expect(first.result == .passed && second.result == .passed && inMemory.result == .passed)
        #expect(ReplayComparison(first, second) == .identical(fingerprint: first.replayFingerprint))
        #expect(ReplayComparison(first, inMemory).isIdentical)
        #expect(first.id != second.id)
    }

    /// Denial: a removal without its approval is refused and removes nothing, and the steps after
    /// it are skipped.
    @Test func aRemovalWithoutItsApprovalIsRefused() async throws {
        let temporary = try TemporaryFolder()
        let folder = try TabletopShowcase.variant(in: temporary) { object in
            object["steps"] = (object["steps"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != "approve-remove-lighthouse" }
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let remove = try #require(run.steps.first { $0.id == name("remove-lighthouse") })
        #expect(remove.result == .failed && remove.receipt == nil)
        #expect(remove.outcome.detail.hasPrefix("Refused: no live approval covers this "), "\(remove.outcome.detail)")
        #expect(remove.outcome.detail.hasSuffix(" through app-ui."), "\(remove.outcome.detail)")
        #expect(run.finalState?.anchors.map(\.id).contains(TabletopShowcase.lighthouse) == true)
    }

    /// Denial: the model-tool adapter cannot place an object; the replay stops at its first change
    /// after Reset Demo, which the model tool may not run either.
    @Test func theModelToolAdapterChangesNothing() async throws {
        let run = await DemoRunner(adapter: .modelTool, store: .inMemory).run(try TabletopShowcase.script())
        checkStepInvariants(run)
        #expect(run.result != .passed)
        #expect(run.steps.compactMap(\.receipt).isEmpty)
        #expect(run.finalState?.anchors.isEmpty == true)
    }

    /// Stale state: a move planned from revision 1 after the object has moved on is answered with a
    /// conflict receipt and changes nothing. The runner counts a conflict as a step that did not
    /// pass, so the showcase leaves this case out.
    @Test func aStaleMoveIsAConflictThatChangesNothing() async throws {
        let temporary = try TemporaryFolder()
        let folder = try TabletopShowcase.variant(in: temporary) { object in
            var steps = object["steps"] as? [[String: Any]] ?? []
            let index = steps.firstIndex { $0["id"] as? String == "turn-lighthouse" }! + 1
            steps.insert([
                "id": "stale-move",
                "request": "6D0B2E55-3C55-4E43-9A69-7C0E8F2B6A11",
                "moveAnchor": ["id": TabletopShowcase.lighthouse.rawValue.uuidString, "expected": 1, "x": 0, "z": 0, "yaw": 0],
            ], at: index)
            object["steps"] = steps
        }
        let run = await DemoRunner.manual().run(try DemoScript(folder: folder))
        checkStepInvariants(run)
        #expect(run.result == .failed)
        let stale = try #require(run.steps.first { $0.id == name("stale-move") })
        #expect(stale.result == .failed)
        let receipt = try #require(stale.receipt)
        #expect(receipt.conflict?.current == revision(3) && receipt.changes.isEmpty && receipt.undo == nil)
        #expect(run.steps.drop { $0.id != name("stale-move") }.dropFirst().allSatisfy { $0.disposition == .skipped })
        let lighthouse = try #require(run.finalState?.anchors.first { $0.id == TabletopShowcase.lighthouse })
        #expect(lighthouse.pose == TabletopShowcase.pose(280, -200, yaw: 15) && lighthouse.revision == revision(3))
    }

    /// Duplicate request: the same placement submitted again under a new request ID is refused as
    /// already existing and adds nothing. (A script cannot repeat a request ID; the TabletopReality
    /// package and Mac hosted qualification tests prove that a retry under the same ID commits once.)
    @Test func aDuplicatePlacementIsRefusedAndAddsNothing() async throws {
        let temporary = try TemporaryFolder()
        let duplicateFolder = try TabletopShowcase.variant(in: temporary) { object in
            var steps = object["steps"] as? [[String: Any]] ?? []
            let index = steps.firstIndex { $0["id"] as? String == "place-lighthouse" }!
            var duplicate = steps[index]
            duplicate["id"] = "duplicate-lighthouse"
            duplicate["request"] = "0B7C83A2-0F87-4C73-8E70-9B6A8F1D2C33"
            steps.insert(duplicate, at: index + 1)
            object["steps"] = steps
        }
        let duplicated = await DemoRunner.manual().run(try DemoScript(folder: duplicateFolder))
        checkStepInvariants(duplicated)
        let duplicate = try #require(duplicated.steps.first { $0.id == name("duplicate-lighthouse") })
        #expect(duplicate.result == .failed && duplicate.receipt == nil)
        #expect(duplicate.outcome.detail.hasSuffix("already exists."), "\(duplicate.outcome.detail)")
        #expect(duplicated.finalState?.anchors.filter { $0.id == TabletopShowcase.lighthouse }.count == 1)
    }

    /// Cancellation: the commits made before the cancel stay; the rest never start.
    @Test func aCancelledReplayCommitsNothingAfterTheCancel() async throws {
        let run = await Task {
            await DemoRunner.manual().run(try! TabletopShowcase.script()) { record in
                if record.id == name("place-cottage") { cancelCurrentTask() }
            }
        }.value
        checkStepInvariants(run)
        #expect(run.result == .notRun)
        let index = try #require(run.steps.firstIndex { $0.id == name("place-cottage") })
        #expect(run.steps[...index].allSatisfy { $0.result == .passed })
        #expect(run.steps[(index + 1)...].allSatisfy { $0.disposition == .cancelled && $0.result == .notRun })
        let placed = Set(run.finalState?.anchors.map(\.id) ?? [])
        #expect(placed == [TabletopShowcase.windmill, TabletopShowcase.cottage])
    }

    /// Anchor steps are validated like every other operation: their fields are fixed, a pose is
    /// whole millimeters within reach with a heading in one turn, and a fixture key is a key.
    @Test func anchorStepsAreValidatedLikeEveryOtherOperation() throws {
        func load(step: Int, _ key: String, _ change: @escaping ([String: Any]) -> [String: Any]) throws -> DemoScriptError? {
            let temporary = try TemporaryFolder()
            let folder = try TabletopShowcase.variant(in: temporary) { object in
                var steps = object["steps"] as? [[String: Any]] ?? []
                steps[step][key] = change(steps[step][key] as? [String: Any] ?? [:])
                object["steps"] = steps
            }
            do {
                _ = try DemoScript(folder: folder)
                return nil
            } catch {
                return error
            }
        }
        func without(_ field: String) -> ([String: Any]) -> [String: Any] { { var entry = $0; entry[field] = nil; return entry } }
        func with(_ field: String, _ value: Any) -> ([String: Any]) -> [String: Any] { { var entry = $0; entry[field] = value; return entry } }
        // Steps 2, 7, and 10 are a placement, a move, and a removal.
        #expect(try load(step: 2, "placeAnchor") { $0 } == nil)
        #expect(try load(step: 2, "placeAnchor", without("fixture")) == .malformed(path: "steps[2].placeAnchor.fixture"))
        #expect(try load(step: 2, "placeAnchor", without("yaw")) == .malformed(path: "steps[2].placeAnchor.yaw"))
        #expect(try load(step: 2, "placeAnchor", with("fixture", "Water Tower")) == .invalidValue(path: "steps[2].placeAnchor.fixture"))
        #expect(try load(step: 2, "placeAnchor", with("x", 5_001)) == .invalidValue(path: "steps[2].placeAnchor.x"))
        #expect(try load(step: 2, "placeAnchor", with("yaw", 360)) == .invalidValue(path: "steps[2].placeAnchor.yaw"))
        #expect(try load(step: 2, "placeAnchor", with("namespace", "user")) == .unknownField(path: "steps[2].placeAnchor.namespace"))
        #expect(try load(step: 2, "placeAnchor", with("worldTransform", [1, 0, 0])) == .unknownField(path: "steps[2].placeAnchor.worldTransform"))
        #expect(try load(step: 7, "moveAnchor", without("expected")) == .malformed(path: "steps[7].moveAnchor.expected"))
        #expect(try load(step: 7, "moveAnchor", with("title", "Renamed")) == .unknownField(path: "steps[7].moveAnchor.title"))
        #expect(try load(step: 10, "removeAnchor", with("x", 0)) == .unknownField(path: "steps[10].removeAnchor.x"))
        #expect(try load(step: 10, "removeAnchor", with("expected", 0)) == .invalidValue(path: "steps[10].removeAnchor.expected"))
    }

    /// A run that places nothing encodes its final state exactly as before anchors were recorded,
    /// so earlier replay fingerprints stay reproducible.
    @Test func aStateWithoutAnchorsEncodesAsBefore() throws {
        let empty = try jsonObject(try Canonical.text(DemoState(collections: [], items: [])))
        #expect(Set(empty.keys) == ["collections", "items"])
        let placed = try jsonObject(try Canonical.text(DemoState(
            collections: [], items: [],
            anchors: [LabAnchor(id: TabletopShowcase.lantern, fixture: try FixtureKey("lantern"), title: "Lantern", pose: .origin)]
        )))
        #expect(Set(placed.keys) == ["collections", "items", "anchors"])
    }
}

// MARK: - Observed runs

/// A LAB-023 run observed outside this package: in the iOS simulator through a UI-test harness,
/// or in the Mac app itself. The facts are read from a file kept outside the repository and the
/// provenance from the built app's Info.plist; `EvidenceRecord` validates the result. No field may
/// carry a UUID, which is what a simulator's identifier is.
struct TabletopRunFacts: Codable {
    /// The record's file name in the export, without `.json`.
    let name: String
    let check: String
    let observedAt: Date
    /// `simulator` or `physical`.
    let path: String
    let platform: String
    let deviceClass: String
    let osVersion: String
    let buildInfoPlist: String
    let inputs: [String]
    let steps: [String]
    let result: RunResult
    let observed: String
    let limitations: [String]

    static let subject = "LAB-023"

    enum Refusal: Error, Equatable {
        case namesADevice(field: String)
        case wrongBuild(sdk: String)
    }

    static func load(_ url: URL) throws -> TabletopRunFacts {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TabletopRunFacts.self, from: Data(contentsOf: url))
    }

    func record() throws -> EvidenceRecord {
        let text: [(String, String)] = [("deviceClass", deviceClass), ("osVersion", osVersion), ("check", check), ("observed", observed)]
            + steps.map { ("steps", $0) } + limitations.map { ("limitations", $0) }
        for (field, value) in text where Self.containsUUID(value) {
            throw Refusal.namesADevice(field: field)
        }
        let info = try #require(NSDictionary(contentsOf: URL(filePath: buildInfoPlist)) as? [String: Any], "the build's Info.plist")
        let provenance = BuildProvenance(infoDictionary: info)
        guard let platform = LabPlatform(rawValue: platform) else { throw EvidenceError.unknownPlatform(platform) }
        let execution: Execution
        switch path {
        case "simulator":
            guard provenance.sdkName.hasPrefix("iphonesimulator") else { throw Refusal.wrongBuild(sdk: provenance.sdkName) }
            execution = .simulator(SimulatedDevice(platform: platform, deviceClass: deviceClass, osVersion: osVersion))
        case "physical":
            guard provenance.sdkName.hasPrefix("macosx") else { throw Refusal.wrongBuild(sdk: provenance.sdkName) }
            execution = .physical(try PhysicalDevice(platform: platform, deviceClass: deviceClass, osVersion: osVersion))
        default:
            throw EvidenceError.blankField("path")
        }
        return try EvidenceRecord(
            subject: Self.subject,
            check: check,
            date: observedAt,
            provenance: provenance,
            execution: execution,
            inputs: inputs,
            steps: steps,
            outcome: RunOutcome(result, detail: observed),
            limitations: limitations
        )
    }

    var exportPath: String { "records/\(name).json" }

    private static func containsUUID(_ value: String) -> Bool {
        value.components(separatedBy: CharacterSet(charactersIn: " \t\n()[]{},;:/=\"'.")).contains { UUID(uuidString: $0) != nil }
    }
}

/// The LAB-023 evidence export: the showcase replayed twice as the app UI on SQLite with the
/// continuous clock, the Mac hosted record, and the observed simulator and Mac runs, all through
/// the rights and privacy review.
///
/// It writes into a temporary folder that is removed afterwards. To keep the export, name a folder
/// and the build facts; with a folder named, every build fact is required:
///
///     LAB_DEMO_EVIDENCE_DIR=<folder> LAB_SOURCE_REVISION=<sha> LAB_SDK_NAME=macosx27.0 \
///     LAB_XCODE_VERSION=27.0 LAB_XCODE_BUILD=27A266a \
///     [LAB_HOST_EVIDENCE_RECORD=<record>] [LAB_023_RUN_FACTS=<facts.json>[,<facts.json>…]] \
///     swift test --package-path Packages/LabDemo --filter TabletopShowcaseEvidence
///
/// `LAB_HOST_EVIDENCE_RECORD` is the record `TabletopHostEvidenceTests` attached, exported from its
/// result bundle. Every record must be for LAB-023 at one source revision. Keep the facts and the
/// export outside the repository, and copy `records/*.json` into `evidence/LAB-023/`.
@Suite struct TabletopShowcaseEvidence {
    private func infoPlist(in folder: TemporaryFolder, sdk: String) throws -> URL {
        let info: [String: Any] = [
            "LabSourceRevision": "0000000", "DTSDKName": sdk, "DTXcode": "2700", "DTXcodeBuild": "27A266a",
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LabBuildProfile": "CoreLocal", "MinimumOSVersion": "26.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        return try folder.write(data, to: "\(sdk).plist")
    }

    private func facts(path: String, plist: URL, deviceClass: String? = nil, observed: String = "Observed.") -> TabletopRunFacts {
        TabletopRunFacts(
            name: "run", check: "The virtual table", observedAt: fixedDate, path: path,
            platform: path == "simulator" ? "iOS" : "macOS", deviceClass: deviceClass ?? (path == "simulator" ? "iPhone 17" : "Mac17,14"),
            osVersion: "27.0", buildInfoPlist: plist.path(percentEncoded: false), inputs: ["kit@sha256:00"],
            steps: ["Place, move, turn, remove."], result: .passed, observed: observed, limitations: ["No camera."]
        )
    }

    /// The generator: a simulator record from a simulator build supports `implemented` at most and
    /// is no device proof; a Mac record must come from a Mac build; neither may name a device.
    @Test func recordsKeepTheirPathAndNeverProveMoreThanItAllows() throws {
        let folder = try TemporaryFolder()
        let simulatorPlist = try infoPlist(in: folder, sdk: "iphonesimulator27.0")
        let macPlist = try infoPlist(in: folder, sdk: "macosx27.0")
        let simulator = try facts(path: "simulator", plist: simulatorPlist).record()
        #expect(simulator.path == .simulator && simulator.subject == "LAB-023")
        #expect(simulator.supportedState == .implemented)
        #expect(throws: PromotionError.notPhysical(.simulator)) { try DeviceProof(simulator) }

        let mac = try facts(path: "physical", plist: macPlist).record()
        #expect(mac.path == .physical)
        #expect(throws: TabletopRunFacts.Refusal.wrongBuild(sdk: "macosx27.0")) { try facts(path: "simulator", plist: macPlist).record() }
        #expect(throws: TabletopRunFacts.Refusal.wrongBuild(sdk: "iphonesimulator27.0")) { try facts(path: "physical", plist: simulatorPlist).record() }
        let udid = UUID().uuidString
        #expect(throws: TabletopRunFacts.Refusal.namesADevice(field: "deviceClass")) {
            try facts(path: "simulator", plist: simulatorPlist, deviceClass: "iPhone 17 (\(udid))").record()
        }
        #expect(throws: TabletopRunFacts.Refusal.namesADevice(field: "observed")) {
            try facts(path: "simulator", plist: simulatorPlist, observed: "Ran on \(udid).").record()
        }
    }

    @Test func theShowcaseExportsEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        let keep = environment["LAB_DEMO_EVIDENCE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
        let facts = ["LAB_SOURCE_REVISION", "LAB_SDK_NAME", "LAB_XCODE_VERSION", "LAB_XCODE_BUILD"]
        if keep != nil {
            for fact in facts {
                try #require(environment[fact].map { !$0.isEmpty } == true, "a kept export names \(fact)")
            }
        }
        let provenance = BuildProvenance(
            sourceRevision: environment["LAB_SOURCE_REVISION"] ?? "unknown",
            sdkName: environment["LAB_SDK_NAME"] ?? "unknown",
            xcodeVersion: environment["LAB_XCODE_VERSION"] ?? "unknown",
            xcodeBuild: environment["LAB_XCODE_BUILD"] ?? "unknown"
        )
        var observed: [(String, EvidenceRecord)] = []
        if let path = environment["LAB_HOST_EVIDENCE_RECORD"] {
            let host = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: URL(filePath: path)))
            observed.append(("records/tabletop-reality-host-interaction.json", host))
        }
        for path in (environment["LAB_023_RUN_FACTS"] ?? "").split(separator: ",") {
            let fact = try TabletopRunFacts.load(URL(filePath: String(path)))
            let record = try fact.record()
            try #require(record.provenance.sourceRevision != "unknown" && record.provenance.xcodeBuild != "unknown")
            observed.append((fact.exportPath, record))
        }
        for (path, record) in observed {
            try #require(record.subject == "LAB-023", "\(path)")
            try #require(record.provenance.sourceRevision == provenance.sourceRevision, "one source revision per export: \(path)")
        }

        let script = try TabletopShowcase.script()
        let runner = DemoRunner(adapter: .appUI, store: .temporarySQLite)
        let runs = [await runner.run(script), await runner.run(script)]
        for run in runs { checkStepInvariants(run) }

        // Nothing is recorded unless the replays passed and agree.
        try #require(runs.allSatisfy { $0.result == .passed })
        try #require(ReplayComparison(runs[0], runs[1]).isIdentical)

        let record = try runs[0].evidenceRecord(
            provenance: provenance,
            check: "Tabletop Reality showcase replayed twice from a clean SQLite store as the app-UI adapter; both replays share one fingerprint"
        )
        let preview = try EvidenceExporter().preview(EvidenceExportRequest(
            title: "LAB-023 Tabletop Reality qualification",
            artifacts: [
                try .run(runs[0], at: "runs/app-ui-first.json"),
                try .run(runs[1], at: "runs/app-ui-second.json"),
                try .record(record, at: "records/tabletop-reality-showcase-app-ui.json", tier: .publicFixture),
                try .file("tabletop-reality/script.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/script.json"),
                try .file("tabletop-reality/seed.json", in: Showcase.fixtures, tier: .publicFixture, at: "inputs/seed.json"),
            ] + observed.map { try .record($0.1, at: $0.0, tier: .publicFixture) },
            untested: [
                "The live AR adapter on any device: a source build declares no NSCameraUsageDescription, so no camera, plane, world map, relocalization, or occlusion ran.",
                "A physical iPhone or iPad: no device was used.",
            ],
            provenance: provenance
        ))
        #expect(preview.result == .passed)
        #expect(preview.refused.isEmpty)
        #expect(preview.reviews.count == 5 + observed.count)
        #expect(preview.reviews.allSatisfy { $0.tier == .publicFixture && $0.decision == .approved })

        let temporary = try TemporaryFolder()
        let written = try preview.write(into: keep ?? temporary.url, folderName: "lab-023-tabletop-reality")
        #expect(temporary.files(below: written) == Set(preview.files.map(\.path)) || keep != nil)
        let stored = try JSONDecoder().decode(
            EvidenceRecord.self, from: Data(contentsOf: written.appending(path: "records/tabletop-reality-showcase-app-ui.json"))
        )
        #expect(stored == record)
        #expect(stored.path == .fixture)
        #expect(stored.supportedState == .implemented, "a replay never supports device-verified")
        #expect(stored.inputs == script.inputs.map(\.reference))
        #expect(stored.limitations.first == DemoRun.fixtureLimitation)
        for (path, record) in observed {
            #expect(try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: written.appending(path: path))) == record)
        }
    }
}
