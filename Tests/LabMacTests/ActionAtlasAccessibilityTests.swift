import AppKit
import Foundation
import LabDomain
import SwiftUI
import Testing
@testable import NativeLab

/// LAB-001-B step 5: the Action Atlas screens through the accessibility API, the automated rows of
/// docs/ACCESSIBILITY_REVIEW.md for this experiment. Each test renders the real action browser
/// views inside the running Mac app, reads their accessibility tree, and presses buttons through
/// the accessibility press action.
///
/// This is not a VoiceOver, Voice Control, or Full Keyboard Access pass, and the display
/// conditions are environment overrides, not the system settings. A `withKnownIssue` marks an open
/// finding in the review; it fails when the finding is fixed, so the review is updated with it.
@MainActor
@Suite struct ActionAtlasAccessibilityTests {
    let storeURL: URL

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ActionAtlasAccessibilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storeURL = folder.appending(path: LabStoreLocation.fileName)
    }

    private func startedLibrary() async throws -> LabLibrary {
        let url = storeURL
        let library = LabLibrary(locateStore: { url })
        await library.start()
        try #require(library.phase == .ready)
        return library
    }

    /// The button that runs each action's form.
    private static let runButton: [AtlasAction: String] = [
        .createCollection: "Create Collection", .createItem: "Create Item", .findItems: "Find Items", .getItem: "Get Item",
        .updateItem: "Update Item", .archiveItem: "Archive Item", .restoreItem: "Restore Item", .exportItem: "Export Item",
    ]

    @Test func everyActionRowIsOneElementLedByItsShortcutsTitle() async throws {
        let hosted = AtlasHostedView(VStack { ForEach(AtlasAction.allCases) { AtlasActionRow(action: $0) } })
        defer { hosted.close() }
        let spoken = try await hosted.elements().filter { !$0.label.isEmpty || !$0.value.isEmpty }.map(\.spoken)
        #expect(spoken == AtlasAction.allCases.map { "\($0.title), \($0.summary)" }, "one element per row; the symbol is not read")
    }

    /// Every form names each control by its visible label, and has one button named for what it
    /// does. A change's button stays disabled until its input is complete.
    @Test(arguments: AtlasAction.allCases)
    func everyFormNamesItsControlsAndItsOneAction(_ action: AtlasAction) async throws {
        let library = try await startedLibrary()
        let hosted = AtlasHostedView(AtlasActionForm(action: action).environment(library))
        defer { hosted.close() }
        let elements = try await hosted.elements()

        let controls = elements.filter { ["AXTextField", "AXPopUpButton", "AXCheckBox"].contains($0.role) }
        for control in controls {
            #expect(!control.name.isEmpty, "\(action.title): a \(control.role) has no name\n\(elements.dump)")
        }
        let buttons = elements.filter { $0.role == "AXButton" && !$0.isScrollBarPart }
        let run = try #require(Self.runButton[action])
        #expect(buttons.map(\.label) == [run], "\(action.title)\n\(elements.dump)")
        #expect(buttons.first?.isEnabled == (action == .findItems), "only Find Items runs with its inputs as they start")
    }

    /// Find Items runs through its accessible button under every display condition, and each
    /// result is one element that starts with the item's title.
    @Test(arguments: DisplayConditions.all)
    func findItemsRunsThroughItsButtonAndReadsOneElementPerItem(_ conditions: DisplayConditions) async throws {
        let library = try await startedLibrary()
        let hosted = AtlasHostedView(AtlasActionForm(action: .findItems).environment(library), conditions: conditions)
        defer { hosted.close() }
        #expect(try await hosted.press("Find Items"), "\(conditions)")
        let elements = try await hosted.elements(until: { $0.contains { $0.role == "AXHeading" && $0.label == "12 items" } })
        let results = elements.filter { $0.role == "AXStaticText" && $0.value.contains("Demo sample") }
        #expect(results.count == 12, "\(conditions)\n\(elements.dump)")
        #expect(results.first?.value.hasPrefix("Amber swatch, Pigment swatches") == true, "\(conditions)")
    }

    /// Open finding (rule 5 in docs/ACCESSIBILITY_REVIEW.md): a found item's row reads the middle
    /// dot between its collection and "Demo sample" instead of a comma. When the row is fixed,
    /// this known issue stops occurring, the test fails, and the review is updated.
    @Test func foundItemRowsReadWithCommasNotMiddleDots() async throws {
        let library = try await startedLibrary()
        let hosted = AtlasHostedView(AtlasActionForm(action: .findItems).environment(library))
        defer { hosted.close() }
        #expect(try await hosted.press("Find Items"))
        let elements = try await hosted.elements(until: { $0.contains { $0.role == "AXHeading" && $0.label == "12 items" } })
        let results = elements.filter { $0.role == "AXStaticText" && $0.value.contains("Demo sample") }
        try #require(results.count == 12)
        withKnownIssue("Action Atlas item rows join the collection and \"Demo sample\" with a middle dot") {
            #expect(!results.contains { $0.value.contains("·") })
        }
    }

    /// A change typed into its named field and run through its accessible button commits, shows
    /// its result in words, and leaves a receipt row that names its status.
    @Test func createCollectionRunsFromItsNamedControlsAndShowsItsReceipt() async throws {
        let library = try await startedLibrary()
        var inspected: [ReceiptRecord] = []
        let hosted = AtlasHostedView(AtlasActionForm(action: .createCollection) { inspected.append($0) }.environment(library))
        defer { hosted.close() }
        #expect(try await hosted.type("Field notes", intoFieldNamed: "Title"))
        let enabled = try await hosted.elements(until: { $0.contains { $0.role == "AXButton" && $0.label == "Create Collection" && $0.isEnabled } })
        #expect(enabled.contains { $0.role == "AXButton" && $0.label == "Create Collection" && $0.isEnabled }, "\(enabled.dump)")

        #expect(try await hosted.press("Create Collection"))
        let done = try await hosted.elements(until: { $0.contains { $0.role == "AXHeading" && $0.label == "Receipt" } })
        let record = try #require(library.latestReceipt)
        #expect(record.receipt.admitted.operation.kind == .createCollection)
        #expect(record.receipt.admitted.adapter == .appUI)
        #expect(inspected.map(\.id) == [record.id], "the Mac opens the receipt in the inspector")
        #expect(done.contains { $0.role == "AXHeading" && $0.label == "Result" }, "\(done.dump)")
        #expect(done.contains { $0.spoken.contains("Field notes") }, "the result says what was made\n\(done.dump)")
        let receiptRow = try #require(done.first { $0.role == "AXButton" && $0.label.contains("Status: Committed") }, "\(done.dump)")
        #expect(receiptRow.label.hasPrefix("Create Collection"))
        #expect(receiptRow.hint == "Shows the receipt in the inspector.")
    }
}

// MARK: - Hosting and reading

/// One accessibility element of a hosted view, with the name an assistive app would read.
struct AtlasElement: CustomStringConvertible {
    let role: String
    let label: String
    let value: String
    let hint: String
    /// The text of the element that titles this one, such as a form row's visible label.
    let title: String
    let isEnabled: Bool
    let depth: Int
    let parentRole: String
    let object: NSObject

    /// What names the element: its label, or else the element that titles it.
    var name: String { label.isEmpty ? title : label }

    /// Label and value together, as they are read.
    var spoken: String { [label, value].filter { !$0.isEmpty }.joined(separator: ", ") }

    var isScrollBarPart: Bool { parentRole == "AXScrollBar" }

    var description: String {
        [String(repeating: "  ", count: depth) + role,
         label.isEmpty ? nil : "label=\"\(label)\"",
         value.isEmpty ? nil : "value=\"\(value)\"",
         title.isEmpty ? nil : "title=\"\(title)\"",
         hint.isEmpty ? nil : "hint=\"\(hint)\"",
         isEnabled ? nil : "disabled"]
            .compactMap(\.self).joined(separator: " ")
    }
}

extension [AtlasElement] {
    var dump: String { map(\.description).joined(separator: "\n") }
}

/// A SwiftUI view in an off-screen window inside the running app, read and operated through its
/// accessibility elements. Like `HostedView`, with the titling element read too.
@MainActor
final class AtlasHostedView {
    private let window: NSWindow
    private let host: NSView

    init<V: View>(_ view: V, conditions: DisplayConditions = .standard) {
        let selector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        _ = NSApp.perform(selector, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        host = NSHostingView(rootView: view.displayConditions(conditions))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 1_400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
    }

    func close() { window.close() }

    /// Every element in reading order, once `condition` holds or two seconds pass.
    func elements(until condition: ([AtlasElement]) -> Bool = { _ in true }) async throws -> [AtlasElement] {
        var found: [AtlasElement] = []
        for _ in 0..<10 {
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

    /// Types into the text field titled `name` through its field editor, as typing does. The
    /// field is found by its accessibility name.
    func type(_ text: String, intoFieldNamed name: String) async throws -> Bool {
        guard let element = try await elements().first(where: { $0.role == "AXTextField" && $0.name == name }),
              let field = (element.object as? NSTextField) ?? Self.textFields(in: host).first else { return false }
        guard window.makeFirstResponder(field), let editor = field.currentEditor() else { return false }
        editor.insertText(text)
        return true
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { subview -> [NSTextField] in
            if let field = subview as? NSTextField, field.isEditable { return [field] }
            return textFields(in: subview)
        }
    }

    private func read() -> [AtlasElement] {
        var elements: [AtlasElement] = []
        func visit(_ element: Any, depth: Int, parentRole: String) {
            guard depth < 40, let object = element as? NSObject else { return }
            let role = Self.text(object, "accessibilityRole")
            let titleElement = Self.read(object, "accessibilityTitleUIElement") as? NSObject
            elements.append(AtlasElement(
                role: role,
                label: Self.text(object, "accessibilityLabel"),
                value: Self.text(object, "accessibilityValue"),
                hint: Self.text(object, "accessibilityHelp"),
                title: titleElement.map { Self.text($0, "accessibilityLabel").isEmpty ? Self.text($0, "accessibilityValue") : Self.text($0, "accessibilityLabel") } ?? "",
                isEnabled: Self.read(object, "isAccessibilityEnabled", key: "accessibilityEnabled") as? Bool ?? true,
                depth: depth,
                parentRole: parentRole,
                object: object
            ))
            for child in Self.read(object, "accessibilityChildren") as? [Any] ?? [] {
                visit(child, depth: depth + 1, parentRole: role)
            }
        }
        visit(host, depth: 0, parentRole: "")
        return elements
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
