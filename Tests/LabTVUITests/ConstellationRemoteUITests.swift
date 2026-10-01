import XCTest

/// LAB-019-B on Apple TV, driven with the Siri Remote alone: open Local Constellation from its
/// detail page, ask to pair the simulated display, read the code the simulated conductor shows,
/// cancel on the display, and press Menu to leave. Nothing is paired, and the live section's Join
/// button is never pressed, so nothing is browsed on the network. Runs in the tvOS simulator;
/// each stage attaches a screenshot.
///
/// The code is not typed: on Apple TV that opens the system keyboard, which this test does not
/// drive. `ConstellationTVTests` pairs the simulation through the model inside the app.
@MainActor
final class ConstellationRemoteUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testTheRemoteOpensTheShowAsksToPairAndCancelsWithNothingShared() throws {
        // The catalog: walk down to Local Constellation and open its detail page.
        let row = app.cells.containing(.any, identifier: "experiment.LAB-019").firstMatch
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 30), "the catalog list did not appear")
        try press(.down, until: row, upTo: 40)
        remote.press(.select)
        let open = element("detail.open-constellation")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the detail page has no Open Local Constellation")
        try press(.down, until: open, upTo: 3)
        remote.press(.select)

        // The screen: the live section offers Join and has browsed nothing; the simulation's
        // display, controller, and conductor are below it.
        let join = app.buttons["Join a Live Show as the Display"]
        XCTAssertTrue(join.waitForExistence(timeout: 15), "the screen did not appear")
        XCTAssertFalse(app.staticTexts["No conductor found yet. On a Mac or iPhone, choose Host a Live Show."].exists, "something was browsed")
        let askToJoin = app.buttons.matching(NSPredicate(format: "label == %@", "Ask to Join")).firstMatch
        XCTAssertTrue(askToJoin.waitForExistence(timeout: 15), "the simulation did not start")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Ask to Join")).count, 2, "the display and the controller each offer Ask to Join")
        snapshot("1 Local Constellation opened")

        // The display asks to pair: it asks for the code, and the conductor shows it with Allow.
        try press(.down, until: askToJoin, upTo: 8)
        XCTAssertFalse(join.hasFocus)
        remote.press(.select)
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Code '")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 10), "the conductor shows no code")
        let digits = code.label.dropFirst("Code ".count).filter(\.isNumber)
        XCTAssertEqual(digits.count, 6, "the code is read as six digits: \(code.label)")
        XCTAssertTrue(app.textFields["Six digits"].waitForExistence(timeout: 5), "the display does not ask for the code")
        XCTAssertTrue(app.buttons["Allow"].exists, "the conductor offers no Allow")
        snapshot("2 The display asks for the code the conductor shows")

        // Cancel on the display: nothing is paired, and the conductor's Allow goes away.
        let cancel = app.buttons["Cancel"]
        try reach(cancel, trying: [[.up], [.up], [.right], [.up], [.down], [.right]])
        remote.press(.select)
        XCTAssertTrue(app.buttons["Allow"].waitForNonExistence(timeout: 10), "the conductor still offers Allow")
        XCTAssertFalse(app.textFields["Six digits"].exists, "the display still asks for a code")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Ask to Join")).count, 2, "a device was paired")
        XCTAssertTrue(join.exists, "the live section changed")
        snapshot("3 Cancelled on the display, nothing paired")

        // Menu closes the screen and returns to the detail page.
        remote.press(.menu)
        XCTAssertTrue(join.waitForNonExistence(timeout: 10), "Menu did not close the screen")
        XCTAssertTrue(element("experiment.detail").waitForExistence(timeout: 10), "Menu did not return to the detail page")
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func focusedIdentifier() -> String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        guard focused.exists else { return "(nothing)" }
        return focused.identifier.isEmpty ? "(\(focused.label))" : focused.identifier
    }

    private func waitForFocus(on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let focused = expectation(for: NSPredicate(format: "hasFocus == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [focused], timeout: timeout) == .completed
    }

    private func press(_ button: XCUIRemote.Button, until target: XCUIElement, upTo limit: Int) throws {
        for _ in 0...limit {
            if waitForFocus(on: target, timeout: 2) { return }
            remote.press(button)
        }
        XCTFail("focus never reached \(target.identifier); it is on \(focusedIdentifier())")
        throw FocusDidNotArrive()
    }

    /// Presses each group of buttons in turn until the target has focus. A press that cannot
    /// move leaves focus where it is, so a path may hold spare presses.
    private func reach(_ target: XCUIElement, trying path: [[XCUIRemote.Button]]) throws {
        for buttons in path {
            if waitForFocus(on: target, timeout: 1.5) { return }
            for button in buttons { remote.press(button) }
        }
        if waitForFocus(on: target, timeout: 3) { return }
        XCTFail("focus never reached \(target.label); it is on \(focusedIdentifier())")
        throw FocusDidNotArrive()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct FocusDidNotArrive: Error {}
