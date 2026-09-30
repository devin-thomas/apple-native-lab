import Accessibility
import AccessSuperpower
import AppKit
import Foundation
import LabCatalog
import LabDomain
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-035-A: the structure behind each way of finishing the task, read through the same AppKit
/// accessibility getters VoiceOver uses. Each test renders the real views inside the running Mac
/// app over a fresh store seeded from the bundled demo seed, with the practice set archived, and
/// acts only through the accessibility tree: a press, a custom action, or a key press to the list.
///
/// These are automated checks (docs/ACCESSIBILITY_REVIEW.md). They prove labels, custom actions,
/// the chart descriptor, and the keyboard path exist and reach the operation service. They do not
/// prove what VoiceOver speaks, that an Audio Graph plays, or how Voice Control or Full Keyboard
/// Access behave for a person; those rows stay `not-run` until a person runs them.
@MainActor
@Suite struct AccessSuperpowerAccessibilityTests {
    let storeURL: URL

    static let quartz = ItemID(rawValue: UUID(uuidString: "AF451890-CA80-4DE9-B18B-4007066C9177")!)
    static let vellum = ItemID(rawValue: UUID(uuidString: "6933AC83-9E61-4264-8EB8-0535B3C5E0F8")!)

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AccessSuperpowerAccessibilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appending(path: LabStoreLocation.fileName)
    }

    /// A library on a fresh store, with the six practice samples archived through the session's
    /// own Set Up Practice path.
    private func practicedLibrary() async throws -> LabLibrary {
        let url = storeURL
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        let session = AccessTaskSession()
        #expect(session.status(in: library) == .nothingArchived)
        session.setUpPractice(in: library)
        try await until { !session.isRunning }
        #expect(session.message == "Archived 6 practice samples. Each has its own receipt.")
        #expect(AccessTaskSession.tally(library).collections.map(\.archivedCount) == [2, 3, 1])
        return library
    }

    // MARK: The chart and its Audio Graph

    /// The chart is one container named for it, carrying an `AXChartDescriptor` whose axes and
    /// series are the chart's own (the exact values are fixed in Fixtures/access/ and checked by
    /// the package tests).
    @Test func theChartCarriesItsAudioGraphDescriptor() async throws {
        let library = try await practicedLibrary()
        let tally = AccessTaskSession.tally(library)
        let hosted = AccessHostedView(ArchiveChart(tally: tally) { _ in })
        defer { hosted.close() }
        let elements = try await hosted.elements()
        let charts = elements.filter { $0.chartDescriptor != nil }
        #expect(charts.count == 1, "one descriptor, on the chart container\n\(elements.dump)")
        let chart = try #require(charts.first)
        #expect(chart.label == "Archived samples by collection")
        let descriptor = try #require(chart.chartDescriptor)
        let expected = ChartSemantics(tally: tally)
        #expect(descriptor.title == "Archived samples by collection")
        #expect(descriptor.summary == expected.summary)
        #expect(descriptor.summary?.hasPrefix("Mineral specimens has the most archived samples: 3 of 4.") == true)
        let xAxis = try #require(descriptor.xAxis as? AXCategoricalDataAxisDescriptor)
        #expect(xAxis.title == "Collection")
        #expect(xAxis.categoryOrder == ["Pigment swatches", "Mineral specimens", "Paper stock"])
        let yAxis = try #require(descriptor.yAxis)
        #expect(yAxis.title == "Archived samples")
        #expect(yAxis.range == 0...4)
        #expect(yAxis.valueDescriptionProvider(3) == "3 archived samples")
        #expect(descriptor.series.map(\.name) == ["Archived samples"])
        let values = descriptor.series.first?.dataPoints.map { $0.yValue?.value(forKey: "number") as? Double }
        #expect(values == [2, 3, 1])
    }

    /// Each bar is one element: the collection, then its count, and a Restore action for each
    /// archived sample in it.
    @Test func eachBarReadsItsCountAndOffersItsRestoreActions() async throws {
        let library = try await practicedLibrary()
        let hosted = AccessHostedView(ArchiveChart(tally: AccessTaskSession.tally(library)) { _ in })
        defer { hosted.close() }
        let bars = try await hosted.elements().filter { !$0.actions.isEmpty }
        #expect(bars.map(\.label) == ["Pigment swatches", "Mineral specimens", "Paper stock"])
        #expect(bars.map(\.value) == ["2 of 4 samples archived", "3 of 4 samples archived, the most", "1 of 4 samples archived"])
        #expect(bars.map(\.actions) == [
            ["Restore Cobalt swatch", "Restore Ochre swatch"],
            ["Restore Banded agate slice", "Restore Obsidian flake", "Restore Quartz point"],
            ["Restore Tracing vellum"],
        ])
    }

    /// VoiceOver's path and the Audio Graph's: a bar's custom action restores through the operation
    /// service as the app UI, the receipt opens in the inspector, and the page says the task is done.
    @Test func aBarsRestoreActionFinishesTheTask() async throws {
        let library = try await practicedLibrary()
        let window = MainWindowState()
        window.destination = .accessSuperpower
        let hosted = AccessHostedView(AccessSuperpowerDetailColumn(window: window, session: window.access).environment(library))
        defer { hosted.close() }
        let bar = try #require(try await hosted.elements().first { $0.label == "Mineral specimens" && !$0.actions.isEmpty })
        #expect(bar.perform(action: "Restore Quartz point"))

        let done = try await hosted.elements(until: { $0.contains { $0.spoken.contains("Task done") } })
        let record = try #require(library.latestReceipt)
        #expect(record.receipt.admitted.operation == .restoreItem(id: Self.quartz, expected: Revision(rawValue: 2)!))
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(record.receipt.conflict == nil)
        #expect(record.receipt.summary == "Restored item “Quartz point”.")
        #expect(window.inspectedReceiptID == record.id && window.showsInspector, "the receipt opens in the inspector")
        #expect(window.access.outcome?.task.completesTask == true)
        #expect(done.contains { $0.spoken.contains("Task done: Mineral specimens had the most archived samples (3).") }, "\(done.dump)")
        #expect(done.contains { $0.role == "AXButton" && $0.label.contains("Status: Committed") }, "the receipt row\n\(done.dump)")
        #expect(AccessTaskSession.announcement(for: record, task: window.access.outcome?.task).text
            == "Restored item “Quartz point”. Undo is available. Task done: Mineral specimens had the most archived samples (3).")

        // The receipt's Undo archives the sample again, so the task is to do again.
        #expect(await library.undo(record) != nil)
        #expect(window.access.currentOutcome(in: library) == nil)
        #expect(window.access.status(in: library) == .toDo)
    }

    // MARK: The semantic list (the declared fallback) and the keyboard path

    /// Each collection is a heading read like its bar; each archived sample is one element read as
    /// title, collection, "Archived", then its note, with a Restore action. The list has an
    /// Archived Samples rotor.
    @Test func theListReadsHeadingsAndRowsWithRestoreActionsAndARotor() async throws {
        let library = try await practicedLibrary()
        let window = MainWindowState()
        let hosted = AccessHostedView(AccessSuperpowerListColumn(window: window, session: window.access).environment(library))
        defer { hosted.close() }
        let elements = try await hosted.elements(until: { $0.contains { $0.label.hasPrefix("Quartz point") } })
        let headings = elements.filter { $0.label.hasSuffix("archived") || $0.label.contains("archived, ") }
            .filter { $0.role != "AXOutline" }.map(\.label)
        #expect(headings == [
            "Pigment swatches, 2 of 4 samples archived",
            "Mineral specimens, 3 of 4 samples archived, the most",
            "Paper stock, 1 of 4 samples archived",
        ], "\(elements.dump)")
        let quartz = try #require(elements.first { $0.label.hasPrefix("Quartz point") })
        #expect(quartz.label == "Quartz point, Mineral specimens, Archived, Clear and six-sided, about the length of a thumb.")
        #expect(quartz.actions == ["Restore Quartz point"])
        let list = try #require(elements.first { $0.role == "AXOutline" })
        #expect(list.rotors == ["Archived Samples"])
        #expect(elements.contains { $0.label == "Archived samples, 6 samples" }, "the list names itself with its count")
    }

    /// The Mac keyboard path: with a sample selected in the list, Return restores it through the
    /// same operation. The key goes to the list as AppKit delivers it; no button is pressed.
    @Test func returnInTheListRestoresTheSelectedSample() async throws {
        let library = try await practicedLibrary()
        let window = MainWindowState()
        let hosted = AccessHostedView(AccessSuperpowerListColumn(window: window, session: window.access).environment(library))
        defer { hosted.close() }
        _ = try await hosted.elements(until: { $0.contains { $0.label.hasPrefix("Quartz point") } })
        window.access.selectedSampleID = Self.quartz
        _ = try await hosted.elements()
        #expect(hosted.pressReturnInList())
        try await until { library.latestReceipt?.receipt.admitted.operation.kind == .restoreItem }
        let record = try #require(library.latestReceipt)
        #expect(record.receipt.admitted.operation.target == .item(Self.quartz))
        #expect(record.receipt.conflict == nil)
        #expect(window.access.outcome?.task.completesTask == true)
        #expect(window.inspectedReceiptID == record.id)
        #expect(window.access.selectedSampleID == nil, "the restored sample leaves the list and the selection")
    }

    /// The Mac's own control for the selected sample, pressed as VoiceOver or Voice Control would.
    /// A restore from a collection that did not have the most is a real change with a receipt,
    /// and the page says the task is not done.
    @Test func theSelectedSampleButtonRestoresAndAMissSaysSo() async throws {
        let library = try await practicedLibrary()
        let window = MainWindowState()
        window.access.selectedSampleID = Self.vellum
        let hosted = AccessHostedView(AccessSuperpowerDetailColumn(window: window, session: window.access).environment(library))
        defer { hosted.close() }
        let button = try #require(try await hosted.elements().first { $0.role == "AXButton" && $0.label == "Restore Tracing vellum" })
        #expect(button.hint == "Returns the sample to its collection. The receipt offers an undo.")
        #expect(try await hosted.press("Restore Tracing vellum"))
        let after = try await hosted.elements(until: { $0.contains { $0.spoken.contains("Task not done") } })
        #expect(library.latestReceipt?.receipt.admitted.operation.target == .item(Self.vellum))
        #expect(window.access.outcome?.task.completesTask == false)
        #expect(after.contains { $0.spoken.contains("Task not done: Paper stock had 1 archived sample, and Mineral specimens had the most (3).") }, "\(after.dump)")
        #expect(window.access.status(in: library) == .toDo)
    }

    // MARK: Without the Audio Graph, and under every display condition

    /// The declared fallback: with no chart descriptor, the page still has the summary, every
    /// collection's count, and a Restore button on every archived sample, and the task finishes.
    @Test(arguments: DisplayConditions.all)
    func withoutTheAudioGraphTheSummaryAndListFinishTheTask(_ conditions: DisplayConditions) async throws {
        let library = try await practicedLibrary()
        let hosted = AccessHostedView(
            NavigationStack { AccessSuperpowerPage() }
                .environment(library)
                .environment(\.accessSonification, .unavailable),
            conditions: conditions
        )
        defer { hosted.close() }
        let elements = try await hosted.elements(until: { $0.contains { $0.label == "Restore Quartz point" } })
        #expect(!elements.contains { $0.chartDescriptor != nil }, "no descriptor on this route")
        #expect(elements.contains { $0.spoken.contains("Mineral specimens has the most archived samples: 3 of 4.") }, "the summary\n\(elements.dump)")
        #expect(elements.contains { $0.spoken.contains("The Audio Graph is unavailable here.") })
        let restores = elements.filter { $0.role == "AXButton" && $0.label.hasPrefix("Restore ") && $0.label != "Reset Practice" }
        #expect(Set(restores.map(\.label)) == ["Restore Cobalt swatch", "Restore Ochre swatch", "Restore Banded agate slice",
                                              "Restore Obsidian flake", "Restore Quartz point", "Restore Tracing vellum"], "\(conditions)")
        #expect(try await hosted.press("Restore Quartz point"), "\(conditions)")
        let done = try await hosted.elements(until: { $0.contains { $0.label == "Task: Done" } })
        #expect(done.contains { $0.label == "Task: Done" }, "\(conditions)\n\(done.dump)")
        #expect(library.latestReceipt?.receipt.admitted.operation.kind == .restoreItem)
    }

    /// With the route on, the same page carries the descriptor.
    @Test func thePageCarriesTheDescriptorWhenTheRouteHasIt() async throws {
        let library = try await practicedLibrary()
        let hosted = AccessHostedView(NavigationStack { AccessSuperpowerPage() }.environment(library))
        defer { hosted.close() }
        let elements = try await hosted.elements(until: { $0.contains { $0.chartDescriptor != nil } })
        #expect(elements.filter { $0.chartDescriptor != nil }.count == 1, "\(elements.dump)")
        #expect(elements.contains { $0.spoken.contains("This build attaches the chart's Audio Graph") })
    }

    // MARK: Reaching the experiment

    @Test func theMenuOpensTheExperimentWithCommandFive() throws {
        let items = Self.menuItems(NSApp.mainMenu)
        let item = try #require(items.first { $0.title == "Access as a Superpower" && !$0.keyEquivalent.isEmpty })
        #expect(item.keyEquivalent == "5")
        #expect(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command)
        #expect(SidebarDestination(storageKey: SidebarDestination.accessSuperpower.storageKey) == .accessSuperpower)
    }

    /// Only LAB-035's catalog page offers the experiment, and on the Mac its button shows the
    /// experiment in the window that holds the page.
    @Test func onlyItsCatalogPageOffersTheExperiment() async throws {
        let registry = try ExperimentRegistry.bundled()
        for id in ["LAB-035", "LAB-001"] {
            let experiment = try #require(registry.experiment(id: id))
            let window = MainWindowState()
            let hosted = AccessHostedView(ExperimentDetailView(experiment: experiment).environment(window))
            defer { hosted.close() }
            let offered = try await hosted.elements().contains { $0.role == "AXButton" && $0.label == "Open Access as a Superpower" }
            #expect(offered == (id == "LAB-035"), "\(id)")
            if offered {
                #expect(try await hosted.press("Open Access as a Superpower"))
                try await until { window.destination == .accessSuperpower }
            }
        }
    }

    // MARK: Helpers

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<50 where !condition() {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(condition())
    }

    private static func menuItems(_ menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        return menu.items.flatMap { [$0] + menuItems($0.submenu) }
    }
}

// MARK: - Hosting and reading

/// One accessibility element, with the parts this experiment adds: custom actions, custom rotors,
/// and a chart descriptor.
struct AccessElement: CustomStringConvertible {
    let role: String
    let label: String
    let value: String
    let hint: String
    let isEnabled: Bool
    let depth: Int
    let actions: [String]
    let rotors: [String]
    let chartDescriptor: AXChartDescriptor?
    let object: NSObject

    var spoken: String { [label, value].filter { !$0.isEmpty }.joined(separator: ", ") }

    /// Performs the custom action with this name, as VoiceOver's actions menu does.
    func perform(action name: String) -> Bool {
        let actions = object.value(forKey: "accessibilityCustomActions") as? [NSAccessibilityCustomAction] ?? []
        guard let action = actions.first(where: { $0.name == name }) else { return false }
        if let handler = action.handler { return handler() }
        guard let target = action.target as? NSObject, let selector = action.selector else { return false }
        _ = target.perform(selector, with: action)
        return true
    }

    var description: String {
        [String(repeating: "  ", count: depth) + role,
         label.isEmpty ? nil : "label=\"\(label)\"",
         value.isEmpty ? nil : "value=\"\(value)\"",
         hint.isEmpty ? nil : "hint=\"\(hint)\"",
         actions.isEmpty ? nil : "actions=\(actions)",
         rotors.isEmpty ? nil : "rotors=\(rotors)",
         chartDescriptor == nil ? nil : "chart",
         isEnabled ? nil : "disabled"]
            .compactMap(\.self).joined(separator: " ")
    }
}

extension [AccessElement] {
    var dump: String { map(\.description).joined(separator: "\n") }
}

/// A SwiftUI view in an off-screen window inside the running app, read and operated through its
/// accessibility elements the way an assistive app would.
@MainActor
final class AccessHostedView {
    private let window: NSWindow
    private let host: NSView

    init<V: View>(_ view: V, conditions: DisplayConditions = .standard) {
        let selector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        _ = NSApp.perform(selector, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        host = NSHostingView(rootView: view.displayConditions(conditions))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 2_400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
    }

    func close() { window.close() }

    /// Every element in reading order, once `condition` holds or three seconds pass.
    func elements(until condition: ([AccessElement]) -> Bool = { _ in true }) async throws -> [AccessElement] {
        var found: [AccessElement] = []
        for _ in 0..<15 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            found = read()
            if condition(found) { break }
        }
        return found
    }

    /// Presses the enabled button with this label, as VoiceOver's VO-Space or Voice Control's
    /// "Tap" does.
    func press(_ label: String) async throws -> Bool {
        guard let button = try await elements().first(where: { $0.role == "AXButton" && $0.label == label && $0.isEnabled }) else {
            return false
        }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard button.object.responds(to: selector) else { return false }
        _ = button.object.perform(selector)
        return true
    }

    /// A key the list receives from the keyboard.
    enum ListKey {
        case down
        case up
        case enter

        var characters: String {
            switch self {
            case .down: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
            case .up: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
            case .enter: "\r"
            }
        }

        var keyCode: UInt16 {
            switch self {
            case .down: 125
            case .up: 126
            case .enter: 36
            }
        }

        var modifierFlags: NSEvent.ModifierFlags {
            self == .enter ? [] : [.numericPad, .function]
        }
    }

    /// Gives the list keyboard focus and sends it Return, as AppKit delivers a key press.
    func pressReturnInList() -> Bool {
        pressKeysInList([.enter])
    }

    /// Gives the list keyboard focus and sends it each key, down and up, as AppKit delivers a key
    /// press. No selection is set and no button is pressed.
    func pressKeysInList(_ keys: [ListKey]) -> Bool {
        guard let list = Self.first(NSOutlineView.self, in: host) ?? Self.first(NSTableView.self, in: host) else { return false }
        window.makeKey()
        guard window.firstResponder === list || window.makeFirstResponder(list) else { return false }
        for key in keys {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: key.modifierFlags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: key.characters,
                    charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.keyCode
                ) else { return false }
                window.sendEvent(event)
            }
        }
        return true
    }

    private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = first(type, in: subview) { return match }
        }
        return nil
    }

    private func read() -> [AccessElement] {
        var elements: [AccessElement] = []
        func visit(_ element: Any, depth: Int) {
            guard depth < 40, let object = element as? NSObject else { return }
            elements.append(AccessElement(
                role: Self.text(object, "accessibilityRole").isEmpty
                    ? Self.legacy(object, "AXRole") as? String ?? "" : Self.text(object, "accessibilityRole"),
                label: Self.text(object, "accessibilityLabel"),
                // An element without a role of its own, such as a chart bar here and in Swift Charts,
                // carries its value as the value description.
                value: Self.text(object, "accessibilityValue").isEmpty
                    ? Self.text(object, "accessibilityValueDescription") : Self.text(object, "accessibilityValue"),
                hint: Self.text(object, "accessibilityHelp"),
                isEnabled: Self.read(object, "isAccessibilityEnabled", key: "accessibilityEnabled") as? Bool ?? true,
                depth: depth,
                actions: (Self.read(object, "accessibilityCustomActions") as? [NSAccessibilityCustomAction] ?? []).map(\.name),
                rotors: (Self.read(object, "accessibilityCustomRotors") as? [NSAccessibilityCustomRotor] ?? []).map(\.label),
                chartDescriptor: Self.read(object, "accessibilityChartDescriptor") as? AXChartDescriptor,
                object: object
            ))
            var children = Self.read(object, "accessibilityChildren") as? [Any] ?? []
            if children.isEmpty { children = Self.legacy(object, "AXChildren") as? [Any] ?? [] }
            for child in children {
                visit(child, depth: depth + 1)
            }
        }
        visit(host, depth: 0)
        return elements
    }

    /// A list's rows and cells answer only the attribute-based API, as they do for VoiceOver.
    private static func legacy(_ object: NSObject, _ attribute: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector, with: attribute)?.takeUnretainedValue()
    }

    private static func read(_ object: NSObject, _ getter: String, key: String? = nil) -> Any? {
        guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
        return object.value(forKey: key ?? getter)
    }

    private static func text(_ object: NSObject, _ getter: String) -> String {
        switch read(object, getter) {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        case let other?: "\(other)"
        case nil: ""
        }
    }
}
