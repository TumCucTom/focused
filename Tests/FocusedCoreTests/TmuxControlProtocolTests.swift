import XCTest
@testable import FocusedCore

final class TmuxControlProtocolTests: XCTestCase {
    func testParseLine_begin() {
        XCTAssertEqual(
            TmuxControlProtocol.parseLine("%begin 1738 1 0"),
            .begin(tag: 1738, flags: ["1", "0"])
        )
    }

    func testParseLine_end() {
        XCTAssertEqual(
            TmuxControlProtocol.parseLine("%end 1738 1 0"),
            .end(tag: 1738, flags: ["1", "0"])
        )
    }

    func testParseLine_field_noTag() {
        XCTAssertEqual(
            TmuxControlProtocol.parseLine("%session-name $1 agent-a"),
            .field(tag: "1", name: "session-name", values: ["agent-a"])
        )
    }

    func testParseLine_field_typedTag() {
        // Some tmux fields have a non-pane tag, e.g. %layout-change ...
        XCTAssertEqual(
            TmuxControlProtocol.parseLine("%output %1 hello world"),
            .field(tag: "1", name: "output", values: ["hello", "world"])
        )
    }

    func testParseLine_pureOutput() {
        XCTAssertEqual(
            TmuxControlProtocol.parseLine("hello world"),
            .output("hello world")
        )
    }

    func testParseLine_empty() {
        XCTAssertEqual(
            TmuxControlProtocol.parseLine(""),
            .output("")
        )
    }

    func testSplitValues_handlesQuoted() {
        XCTAssertEqual(
            TmuxControlProtocol.splitValues("a \"b c\" d"),
            ["a", "b c", "d"]
        )
    }

    func testParseFullBlock_yieldsExpectedEvents() {
        let block = """
        %begin 1738 1 0
        %session-name $1 agent-a
        %session-windows $1 1
        %end 1738 1 0
        """
        let events = TmuxControlProtocol.parse(block: block, commandTag: 1738)
        XCTAssertEqual(events.count, 4)
        if case let .begin(tag, _) = events[0] { XCTAssertEqual(tag, 1738) } else { XCTFail() }
        if case let .field(_, name, values) = events[1] {
            XCTAssertEqual(name, "session-name")
            XCTAssertEqual(values, ["agent-a"])
        } else { XCTFail() }
        if case let .end(tag, _) = events[3] { XCTAssertEqual(tag, 1738) } else { XCTFail() }
    }
}
