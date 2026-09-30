import XCTest

/// Drives the Apple TV host with the Siri Remote alone (XCUIRemote), as a person would: focus
/// reaches the catalog, an experiment's detail page, and Readiness, and Menu always leads back,
/// from the detail page to the list, from the list to the tab bar, and from there to Home.
///
/// Each stage attaches a screenshot to the test result for review.
@MainActor
final class LabTVRemoteUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testRemoteReachesEveryScreenAndMenuLeadsBack() throws {
        // Catalog: the first experiment takes focus within a few presses of Down. A list row's
        // focus belongs to its cell, which contains the identified link.
        let firstExperiment = row("experiment.LAB-001")
        XCTAssertTrue(firstExperiment.waitForExistence(timeout: 30), "the catalog list did not appear")
        XCTAssertTrue(element("catalog.summary").exists, "the catalog summary is missing")
        try press(.down, until: firstExperiment, upTo: 4)
        snapshot("1 Catalog, first experiment focused")

        // Down moves through the list.
        remote.press(.down)
        XCTAssertTrue(waitForFocus(on: row("experiment.LAB-004")), "Down did not move to the next experiment; focus is on \(focusedIdentifier())")
        remote.press(.up)
        XCTAssertTrue(waitForFocus(on: firstExperiment))

        // Select opens the detail page, where focus lands on a card and Down walks the cards.
        remote.press(.select)
        let detail = element("experiment.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "Select did not open the detail page")
        XCTAssertTrue(element("detail.header").label.contains("Action Atlas"), "the detail page shows the wrong experiment")
        let firstCard = focusedIdentifier()
        XCTAssertTrue(firstCard.hasPrefix("detail."), "no card took focus on the detail page; focus is on \(firstCard)")
        remote.press(.down)
        remote.press(.down)
        let laterCard = try waitForFocusedIdentifier(changedFrom: firstCard)
        XCTAssertTrue(laterCard.hasPrefix("detail."), "Down left the detail page; focus is on \(laterCard)")
        snapshot("2 Detail, card focused after Down")

        // Menu closes the page and returns focus to the experiment it came from.
        remote.press(.menu)
        XCTAssertTrue(detail.waitForNonExistence(timeout: 10), "Menu did not close the detail page")
        XCTAssertTrue(waitForFocus(on: firstExperiment), "focus did not return to the experiment; it is on \(focusedIdentifier())")

        // Menu from the list moves focus to the tab bar, and Right selects Readiness.
        remote.press(.menu)
        let catalogTab = app.tabBars.buttons["Catalog"]
        XCTAssertTrue(waitForFocus(on: catalogTab), "Menu did not move focus to the tab bar; it is on \(focusedIdentifier())")
        remote.press(.right)
        let readinessTab = app.tabBars.buttons["Readiness"]
        XCTAssertTrue(waitForFocus(on: readinessTab))
        XCTAssertTrue(element("readiness").waitForExistence(timeout: 10), "Readiness did not appear")

        // Readiness: Probe Again takes focus first; the probes have measured and say when.
        let probeAgain = element("readiness.probe-again")
        try press(.down, until: probeAgain, upTo: 3)
        let freshness = element("readiness.freshness")
        XCTAssertTrue(freshness.waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor(freshness, labelContaining: "Measured"), "the probes did not report a measured time: \(freshness.label)")
        snapshot("3 Readiness, Probe Again focused")

        // Down reaches a capability; Select shows its gates. More Down presses walk the page.
        let bluetooth = element("readiness.probe.bluetooth")
        try press(.down, until: bluetooth, upTo: 3)
        remote.press(.select)
        XCTAssertTrue(element("readiness.gates.bluetooth").waitForExistence(timeout: 5), "Select did not show the gates")
        snapshot("4 Readiness, Bluetooth gates shown")
        for _ in 0..<6 { remote.press(.down) }
        let deeper = focusedIdentifier()
        XCTAssertTrue(deeper.hasPrefix("readiness."), "Down left the Readiness page; focus is on \(deeper)")
        XCTAssertNotEqual(deeper, "readiness.probe.bluetooth")
        snapshot("5 Readiness, focus further down the page")

        // Menu returns focus to the tab bar, and Menu again leaves the app for the Home screen.
        remote.press(.menu)
        XCTAssertTrue(waitForFocus(on: readinessTab), "Menu did not return focus to the tab bar; it is on \(focusedIdentifier())")
        remote.press(.menu)
        let left = expectation(for: NSPredicate(format: "state != %d", XCUIApplication.State.runningForeground.rawValue),
                               evaluatedWith: app)
        wait(for: [left], timeout: 10)

        // Bring the app back, so the run ends with the host in front as it began.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The list cell that holds the element with this identifier.
    private func row(_ identifier: String) -> XCUIElement {
        app.cells.containing(.any, identifier: identifier).firstMatch
    }

    private func focusedElement() -> XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    private func focusedIdentifier() -> String {
        let focused = focusedElement()
        guard focused.exists else { return "(nothing)" }
        return focused.identifier.isEmpty ? "(\(focused.label))" : focused.identifier
    }

    private func waitForFocus(on element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let focused = expectation(for: NSPredicate(format: "hasFocus == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [focused], timeout: timeout) == .completed
    }

    private func waitFor(_ element: XCUIElement, labelContaining text: String, timeout: TimeInterval = 15) -> Bool {
        let matches = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        return XCTWaiter.wait(for: [matches], timeout: timeout) == .completed
    }

    private func waitForFocusedIdentifier(changedFrom previous: String) throws -> String {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let current = focusedIdentifier()
            if current != previous { return current }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("focus stayed on \(previous)")
        throw FocusDidNotMove()
    }

    private func press(_ button: XCUIRemote.Button, until target: XCUIElement, upTo limit: Int) throws {
        // A focus query takes about a second on the simulator, so each check waits long enough
        // for focus to settle before the next press; a hasty press would skip past the target.
        for _ in 0...limit {
            if waitForFocus(on: target, timeout: 4) { return }
            remote.press(button)
        }
        XCTFail("\(target) never took focus; focus is on \(focusedIdentifier())\n\(app.debugDescription)")
        throw FocusDidNotMove()
    }

    private struct FocusDidNotMove: Error {}

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
