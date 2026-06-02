import XCTest
@testable import FocusedCore

final class DoneDetectorTests: XCTestCase {
    let detector = DoneDetector(idleThreshold: 1.5)

    func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8)
    }

    func testIdlePane_isIdle() {
        let text = fixture("pane_idle")
        XCTAssertEqual(detector.evaluate(paneText: text, quietFor: 2.0), .idle)
    }

    func testWorkingPane_isWorking_whenRecentlyChanged() {
        let text = fixture("pane_working")
        XCTAssertEqual(detector.evaluate(paneText: text, quietFor: 0.5), .working)
    }

    func testIdlePane_isStillWorking_whenBelowThreshold() {
        let text = fixture("pane_idle")
        XCTAssertEqual(detector.evaluate(paneText: text, quietFor: 0.5), .working)
    }

    func testSpinnerPane_isWorking_evenAfterThreshold() {
        let text = fixture("pane_spinner")
        XCTAssertEqual(detector.evaluate(paneText: text, quietFor: 3.0), .working)
    }

    func testExitedPane_isExited() {
        let text = fixture("pane_exited")
        XCTAssertEqual(detector.evaluate(paneText: text, quietFor: 5.0), .exited)
    }

    func testEmptyPane_isWorking() {
        XCTAssertEqual(detector.evaluate(paneText: "", quietFor: 0.0), .working)
    }

    func testPromptWithTrailingText_isWorking() {
        let text = "❯ hello"
        XCTAssertEqual(detector.evaluate(paneText: text, quietFor: 5.0), .working)
    }

    func testShellPrompt_isExited() {
        XCTAssertEqual(detector.evaluate(paneText: "$ ", quietFor: 5.0), .exited)
    }
}
