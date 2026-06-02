import XCTest
@testable import FocusedCore

@MainActor
final class SidebarStoreTests: XCTestCase {
    func makeSession(_ id: String, status: SessionStatus = .working) -> AgentSession {
        AgentSession(
            id: id,
            name: "agent-\(id)",
            workingDirectory: "/tmp/\(id)",
            status: status
        )
    }

    func testInitialOrder_isInsertionOrder() {
        let store = SidebarStore()
        store.upsert(makeSession("a"))
        store.upsert(makeSession("b"))
        XCTAssertEqual(store.sessions.map(\.id), ["a", "b"])
    }

    func testUpsert_existing_preservesPinAndStatus() {
        let store = SidebarStore()
        var s = makeSession("a")
        s.isPinned = true
        store.upsert(s)
        store.upsert(makeSession("a", status: .working))
        XCTAssertTrue(store.sessions.first?.isPinned ?? false)
    }

    func testBubblingIdle_movesToTop() {
        let store = SidebarStore()
        store.upsert(makeSession("a", status: .working))
        store.upsert(makeSession("b", status: .working))
        store.markIdle(id: "b")
        XCTAssertEqual(store.sessions.map(\.id), ["b", "a"])
    }

    func testPinned_sessionsDoNotBubble() {
        let store = SidebarStore()
        var pinned = makeSession("a", status: .working)
        pinned.isPinned = true
        store.upsert(pinned)
        store.upsert(makeSession("b", status: .working))
        store.markIdle(id: "b")
        XCTAssertEqual(store.sessions.map(\.id), ["a", "b"])
    }

    func testQueueDuringFlash_secondIdleTakesTopAfterFirstSettles() async {
        let store = SidebarStore(flashDuration: 0.1)
        store.upsert(makeSession("a", status: .working))
        store.upsert(makeSession("b", status: .working))
        store.markIdle(id: "a")
        store.markIdle(id: "b")
        XCTAssertEqual(store.sessions.first?.id, "a")
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(store.sessions.first?.id, "b")
    }

    func testRemoveSession() {
        let store = SidebarStore()
        store.upsert(makeSession("a"))
        store.upsert(makeSession("b"))
        store.remove(id: "a")
        XCTAssertEqual(store.sessions.map(\.id), ["b"])
    }

    func testSetPreview() {
        let store = SidebarStore()
        store.upsert(makeSession("a"))
        store.setPreview(id: "a", text: "hello world")
        XCTAssertEqual(store.sessions.first?.previewText, "hello world")
    }

    func testMarkExited() {
        let store = SidebarStore()
        store.upsert(makeSession("a", status: .working))
        store.markExited(id: "a")
        XCTAssertEqual(store.sessions.first?.status, .exited)
    }
}
