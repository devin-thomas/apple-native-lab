import AppKit
import SwiftUI

/// One element of a hosted SwiftUI view's accessibility tree, read through the same AppKit
/// accessibility getters VoiceOver and Voice Control use.
struct AccessibilityNode: CustomStringConvertible {
    let role: String
    let label: String
    let value: String
    let hint: String
    let isEnabled: Bool
    let depth: Int
    fileprivate let object: NSObject

    var isButton: Bool { role == NSAccessibility.Role.button.rawValue }

    var description: String {
        [String(repeating: "  ", count: depth) + role,
         label.isEmpty ? nil : "label=\"\(label)\"",
         value.isEmpty ? nil : "value=\"\(value)\"",
         hint.isEmpty ? nil : "hint=\"\(hint)\"",
         isEnabled ? nil : "disabled"]
            .compactMap(\.self).joined(separator: " ")
    }
}

/// Environment overrides a hosted view is rendered under. They stand in for the system settings
/// inside the test process only; they are not the settings, and a pass here is not a pass with
/// the settings turned on (docs/ACCESSIBILITY_REVIEW.md).
struct DisplayConditions: CustomStringConvertible, Sendable {
    var reduceMotion = false
    var reduceTransparency = false
    var increasedContrast = false
    var differentiateWithoutColor = false
    var dynamicTypeSize: DynamicTypeSize = .large

    static let standard = DisplayConditions()
    static let all: [DisplayConditions] = [
        .standard,
        DisplayConditions(reduceMotion: true),
        DisplayConditions(reduceTransparency: true),
        DisplayConditions(increasedContrast: true),
        DisplayConditions(differentiateWithoutColor: true),
        DisplayConditions(reduceMotion: true, reduceTransparency: true, increasedContrast: true,
                          differentiateWithoutColor: true, dynamicTypeSize: .accessibility5),
    ]

    var description: String {
        let flags = [reduceMotion ? "reduce motion" : nil, reduceTransparency ? "reduce transparency" : nil,
                     increasedContrast ? "increased contrast" : nil,
                     differentiateWithoutColor ? "differentiate without color" : nil,
                     dynamicTypeSize == .large ? nil : "type size \(dynamicTypeSize)"].compactMap(\.self)
        return flags.isEmpty ? "standard" : flags.joined(separator: ", ")
    }
}

extension View {
    func displayConditions(_ conditions: DisplayConditions) -> some View {
        environment(\._accessibilityReduceMotion, conditions.reduceMotion)
            .environment(\._accessibilityReduceTransparency, conditions.reduceTransparency)
            .environment(\._colorSchemeContrast, conditions.increasedContrast ? .increased : .standard)
            .environment(\._accessibilityDifferentiateWithoutColor, conditions.differentiateWithoutColor)
            .environment(\.dynamicTypeSize, conditions.dynamicTypeSize)
    }
}

/// A SwiftUI view rendered in an off-screen window inside the running app, read and operated
/// through its accessibility elements the way an assistive app would.
@MainActor
final class HostedView {
    private let window: NSWindow
    private let host: NSView

    init<V: View>(_ view: V, conditions: DisplayConditions = .standard, size: CGSize = CGSize(width: 560, height: 1_000)) {
        Self.enableAccessibilityTree()
        host = NSHostingView(rootView: view.displayConditions(conditions))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        // SwiftUI builds accessibility nodes only for a window that is ordered in; this one stays
        // far off the visible screen.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
    }

    func close() { window.close() }

    /// Every element in tree order, the order VoiceOver reads them.
    func tree() async throws -> [AccessibilityNode] {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        var nodes: [AccessibilityNode] = []
        func visit(_ element: Any, depth: Int) {
            guard depth < 40, let object = element as? NSObject else { return }
            nodes.append(AccessibilityNode(
                role: Self.read(object, "accessibilityRole") as? String ?? "",
                label: Self.read(object, "accessibilityLabel") as? String ?? "",
                value: Self.read(object, "accessibilityValue").map { "\($0)" } ?? "",
                hint: Self.read(object, "accessibilityHelp") as? String ?? "",
                isEnabled: Self.read(object, "isAccessibilityEnabled", key: "accessibilityEnabled") as? Bool ?? true,
                depth: depth,
                object: object
            ))
            for child in Self.read(object, "accessibilityChildren") as? [Any] ?? [] {
                visit(child, depth: depth + 1)
            }
        }
        visit(host, depth: 0)
        return nodes
    }

    /// Presses the button with this accessibility label, as VoiceOver's VO-Space or Voice
    /// Control's "Tap" does. Returns false when there is no such enabled button.
    func press(_ label: String) async throws -> Bool {
        guard let button = try await tree().first(where: { $0.isButton && $0.label == label && $0.isEnabled }) else {
            return false
        }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard button.object.responds(to: selector) else { return false }
        _ = button.object.perform(selector)
        return true
    }

    /// Reads one Objective-C accessibility getter, checking it exists first.
    private static func read(_ object: NSObject, _ getter: String, key: String? = nil) -> Any? {
        guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
        return object.value(forKey: key ?? getter)
    }

    /// SwiftUI builds its accessibility elements once an assistive client asks the application for
    /// them, which an assistive app does by setting AXEnhancedUserInterface on the application.
    /// Called through the runtime because the setter is the legacy attribute API.
    private static func enableAccessibilityTree() {
        let selector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        _ = NSApp.perform(selector, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }
}

extension [AccessibilityNode] {
    var buttons: [AccessibilityNode] { filter(\.isButton) }

    /// Every label in reading order.
    var labels: [String] { map(\.label).filter { !$0.isEmpty } }

    func first(labeled label: String) -> AccessibilityNode? { first { $0.label == label } }

    var dump: String { map(\.description).joined(separator: "\n") }
}
