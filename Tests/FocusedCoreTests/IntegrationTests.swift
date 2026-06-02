import XCTest
@testable import FocusedCore

/// End-to-end tests that talk to a real `tmux` binary. They are skipped automatically
/// when tmux is not on PATH.
final class TmuxControlClientIntegrationTests: XCTestCase {
    let socketName = "focused-test-\(UUID().uuidString.prefix(6))"

    var hasTmux: Bool {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        if candidates.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return true
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            return path.split(separator: ":").contains { dir in
                FileManager.default.isExecutableFile(atPath: "\(dir)/tmux")
            }
        }
        return false
    }

    func testServerLifecycle() async throws {
        try requireTmux()
        let client = TmuxControlClient(socket: .custom(String(socketName)))
        try await client.ensureServerRunning()
        let alive1 = try await client.serverIsAlive()
        XCTAssertTrue(alive1)
        try await client.restartServer()
        let alive2 = try await client.serverIsAlive()
        XCTAssertTrue(alive2)
    }

    func testSpawnAndListSession() async throws {
        try requireTmux()
        let client = TmuxControlClient(socket: .custom(String(socketName)))
        try await client.ensureServerRunning()
        let sessionName = "agent-\(UUID().uuidString.prefix(6))"
        try await client.newSession(name: sessionName, directory: "/tmp")
        let sessions = try await client.listSessions()
        XCTAssertTrue(sessions.contains { $0.name == sessionName })
        try await client.killSession(sessionName)
        let after = try await client.listSessions()
        XCTAssertFalse(after.contains { $0.name == sessionName })
    }

    func testSendKeysAndCapturePane() async throws {
        try requireTmux()
        let client = TmuxControlClient(socket: .custom(String(socketName)))
        try await client.ensureServerRunning()
        let sessionName = "agent-\(UUID().uuidString.prefix(6))"
        try await client.newSession(name: sessionName, directory: "/tmp")
        try await client.sendKeys("echo HELLO_FOCUSED", to: sessionName)
        // Give tmux a moment to execute the command and render.
        try? await Task.sleep(nanoseconds: 500_000_000)
        let pane = try await client.capturePane(session: sessionName, lines: 50)
        XCTAssertTrue(pane.contains("HELLO_FOCUSED"), "pane was: \(pane)")
        try await client.killSession(sessionName)
    }

    func requireTmux() throws {
        guard hasTmux else {
            throw XCTSkip("tmux not installed on this machine")
        }
    }
}
