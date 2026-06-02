import XCTest
@testable import FocusedCore

final class AgentSessionTests: XCTestCase {
    func testShortDirectory_usesLastPathComponent() {
        let session = AgentSession(id: "x", name: "x", workingDirectory: "/Users/tom/projects/api")
        XCTAssertEqual(session.shortDirectory, "api")
    }

    func testShortDirectory_handlesRoot() {
        let session = AgentSession(id: "x", name: "x", workingDirectory: "/")
        XCTAssertEqual(session.shortDirectory, "/")
    }

    func testShortDirectory_handlesHomeRelative() {
        let session = AgentSession(id: "x", name: "x", workingDirectory: "~/code")
        XCTAssertEqual(session.shortDirectory, "code")
    }

    func testEquality() {
        let a = AgentSession(id: "1", name: "a", workingDirectory: "/a", status: .idle)
        let b = AgentSession(id: "1", name: "a", workingDirectory: "/a", status: .idle)
        XCTAssertEqual(a, b)
    }

    func testInequality_differentStatus() {
        let a = AgentSession(id: "1", name: "a", workingDirectory: "/a", status: .idle)
        let b = AgentSession(id: "1", name: "a", workingDirectory: "/a", status: .working)
        XCTAssertNotEqual(a, b)
    }
}
