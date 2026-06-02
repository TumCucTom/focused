import XCTest
@testable import FocusedCore

/// Verifies that the integration points between TmuxControlClient, SidebarStore,
/// and DoneDetector all work together. Uses a real tmux server. The detector's
/// per-state behavior is covered by unit tests with fixtures; this test only
/// asserts that the integration plumbing (spawn → capture → store) functions.
@MainActor
final class EndToEndPipelineTests: XCTestCase {
    let socketName = "focused-e2e-\(UUID().uuidString.prefix(6))"

    var hasTmux: Bool {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func testSpawnAndCapturePipeline() async throws {
        try requireTmux()

        let client = TmuxControlClient(socket: .custom(String(socketName)))
        try await client.ensureServerRunning()

        let store = SidebarStore()
        let sessionName = "agent-e2e-\(UUID().uuidString.prefix(6))"
        let dir = "/tmp"

        // Spawn
        try await client.newSession(name: sessionName, directory: dir)
        let infos = try await client.listSessions()
        XCTAssertTrue(infos.contains { $0.name == sessionName })

        store.upsert(AgentSession(
            id: sessionName,
            name: sessionName,
            workingDirectory: dir,
            status: .starting,
            lastActivity: Date()
        ))

        // Wait for the shell prompt to appear before sending keys.
        var promptSeen = false
        for _ in 0..<30 {
            let initial = try await client.capturePane(session: sessionName, lines: 20)
            if initial.contains("%") || initial.contains("$") {
                promptSeen = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(promptSeen, "shell prompt never appeared in time")

        // Send a command and verify it appears in the captured pane.
        try await client.sendKeys("echo FOCUSED_PIPELINE_OK", to: sessionName)
        var resultSeen = false
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let pane = try await client.capturePane(session: sessionName, lines: 50)
            if pane.contains("FOCUSED_PIPELINE_OK") {
                resultSeen = true
                store.setPreview(id: sessionName, text: pane.suffix(120).description)
                break
            }
        }
        XCTAssertTrue(resultSeen, "command output never appeared in pane")

        // Verify the session is still alive and the store can reflect the change.
        let stillExists = await client.sessionExists(sessionName)
        XCTAssertTrue(stillExists)
        XCTAssertEqual(store.sessions.first?.id, sessionName)

        // Cleanup
        try await client.killSession(sessionName)
        let after = try await client.listSessions()
        XCTAssertFalse(after.contains { $0.name == sessionName })
    }

    func testDetectorIdentifiesClaudeCodeIdle() {
        // The detector is a pure function — covered by unit tests with fixtures.
        // This is a quick smoke test to make sure the type wires up at runtime.
        let detector = DoneDetector(idleThreshold: 0.5)
        let idleText = "x\n❯\n"
        XCTAssertEqual(detector.evaluate(paneText: idleText, quietFor: 1.0), .idle)
    }

    func requireTmux() throws {
        guard hasTmux else { throw XCTSkip("tmux not installed") }
    }
}
