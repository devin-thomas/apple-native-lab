import XCTest

/// LAB-031 on Apple TV, driven with the Siri Remote alone: open Native Screening Room from its
/// detail page, choose Spanish captions, watch in the theater (the system player, full screen),
/// and press Menu to come back. The captions and the position survive the round trip, and the
/// page says so. Runs in the tvOS simulator; each stage attaches a screenshot.
@MainActor
final class ScreeningRoomRemoteUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testCaptionsSurviveTheTheaterAndMenuReturnsToThePage() throws {
        // The catalog: walk down to Native Screening Room and open its detail page.
        let row = app.cells.containing(.any, identifier: "experiment.LAB-031").firstMatch
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 30), "the catalog list did not appear")
        try press(.down, until: row, upTo: 40)
        remote.press(.select)

        // The detail page's first focusable item is the way in.
        let open = element("detail.open-screening-room")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the detail page has no Open Native Screening Room")
        try press(.down, until: open, upTo: 3)
        remote.press(.select)
        let summary = element("screening.summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "the screening page did not appear")
        XCTAssertTrue(waitFor(summary, labelContaining: "Test Card") || waitFor(summary, labelContaining: "Paused"),
                      "the test card did not open: \(summary.label)")
        snapshot("1 Screening Room opened")

        // Spanish captions, chosen with the remote.
        let spanish = element("screening.caption.es")
        try follow([.down, .down, .right, .right, .right], to: spanish)
        remote.press(.select)
        XCTAssertTrue(waitFor(summary, labelContaining: "Spanish"), "the caption did not change: \(summary.label)")
        snapshot("2 Spanish captions chosen")

        // Watch in Theater: the system player takes the whole screen.
        let theater = element("screening.theater")
        try follow([.left, .left, .up], to: theater)
        remote.press(.select)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        snapshot("3 Theater, the system player")

        // Menu closes the player. A first press may only hide its controls, so press again only
        // while the page is still covered.
        for _ in 0..<3 where !(summary.exists && waitFor(summary, labelContaining: "In the page", timeout: 4)) {
            remote.press(.menu)
        }
        XCTAssertTrue(waitFor(summary, labelContaining: "In the page"), "Menu did not return to the page: \(summary.label)")
        XCTAssertTrue(summary.label.contains("Spanish"), "the captions changed on the way back: \(summary.label)")
        XCTAssertTrue(element("screening.screen").exists, "Menu left the screening page instead of the theater")

        // The receipts show the round trip: the theater opened, and closing it returned the clip
        // to the page. Only the theater's dismissal sends that second command.
        let receipts = element("screening.receipts")
        XCTAssertTrue(receipts.label.contains("to the theater"), "no receipt for opening the theater: \(receipts.label)")
        XCTAssertTrue(receipts.label.contains("to the page"), "no receipt for returning to the page: \(receipts.label)")
        snapshot("4 Back in the page, Spanish kept")
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

    private func waitFor(_ element: XCUIElement, labelContaining text: String, timeout: TimeInterval = 15) -> Bool {
        let matches = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        return XCTWaiter.wait(for: [matches], timeout: timeout) == .completed
    }

    private func press(_ button: XCUIRemote.Button, until target: XCUIElement, upTo limit: Int) throws {
        for _ in 0...limit {
            if waitForFocus(on: target, timeout: 2) { return }
            remote.press(button)
        }
        XCTFail("focus never reached \(target.identifier); it is on \(focusedIdentifier())")
        throw FocusDidNotArrive()
    }

    /// Presses each button in turn until the target has focus. Presses past the end of a row
    /// leave focus where it is, so a path may end with spare presses toward the target.
    private func follow(_ path: [XCUIRemote.Button], to target: XCUIElement) throws {
        for button in path {
            if waitForFocus(on: target, timeout: 1.5) { return }
            remote.press(button)
        }
        if waitForFocus(on: target, timeout: 3) { return }
        XCTFail("focus never reached \(target.identifier); it is on \(focusedIdentifier())")
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
