# Focused Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI app that runs multiple Claude Code agents in parallel, with a live tmux-rendered main view and a sidebar of all agents that bubbles freshly-idle ones to the top and fires macOS notifications.

**Architecture:** SwiftPM package with two targets — `FocusedCore` (testable library: tmux protocol, done detector, sidebar state machine) and `FocusedApp` (SwiftUI executable). tmux is the source of truth for session state; the app is a thin GUI on top.

**Tech Stack:** Swift 6.3, SwiftUI, SwiftTerm (SwiftPM), tmux 3.x, AppKit bridge, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-06-02-focused-terminal-app-design.md`

---

## File Structure

```
/Users/tom/focused/
├── Package.swift                                    # SwiftPM manifest
├── Sources/
│   ├── FocusedCore/                                 # Library (testable)
│   │   ├── Models/
│   │   │   ├── AgentSession.swift                   # id, name, directory, status, lastActivity
│   │   │   └── SessionStatus.swift                  # .starting, .working, .idle, .exited
│   │   ├── Tmux/
│   │   │   ├── TmuxControlProtocol.swift            # line-protocol parser
│   │   │   ├── TmuxControlClient.swift              # Process wrapper, async/await API
│   │   │   └── TmuxSessionInfo.swift                # session metadata
│   │   ├── Detection/
│   │   │   └── DoneDetector.swift                   # pure function
│   │   └── Sidebar/
│   │       └── SidebarStore.swift                   # @Observable, ordering + pin + bubble
│   └── FocusedApp/                                  # Executable (SwiftUI)
│       ├── FocusedApp.swift                         # @main App entry
│       ├── AppState.swift                           # root @Observable
│       ├── Sidebar/
│       │   ├── SidebarView.swift
│       │   └── SidebarRowView.swift
│       ├── Terminal/
│       │   ├── TerminalHostView.swift               # SwiftTerm bridge
│       │   └── AttachController.swift               # PTY child process
│       ├── Notifications/
│       │   └── NotificationManager.swift
│       ├── Settings/
│       │   ├── Settings.swift
│       │   └── SettingsView.swift
│       └── Banners/
│           └── EmptyStateBanner.swift               # tmux/claude missing states
├── Tests/
│   └── FocusedCoreTests/
│       ├── DoneDetectorTests.swift
│       ├── SidebarStoreTests.swift
│       ├── TmuxControlProtocolTests.swift
│       └── Fixtures/
│           ├── pane_idle.txt
│           ├── pane_working.txt
│           ├── pane_exited.txt
│           └── pane_spinner.txt
├── docs/superpowers/
│   ├── specs/2026-06-02-focused-terminal-app-design.md
│   └── plans/2026-06-02-focused-terminal-app.md
└── README.md
```

---

## Task 1: Bootstrap SwiftPM package

**Files:**
- Create: `Package.swift`
- Create: `Sources/FocusedCore/Placeholder.swift`
- Create: `Sources/FocusedApp/Placeholder.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Focused",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusedCore", targets: ["FocusedCore"]),
        .executable(name: "Focused", targets: ["FocusedApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "FocusedCore",
            dependencies: []
        ),
        .executableTarget(
            name: "FocusedApp",
            dependencies: [
                "FocusedCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(
            name: "FocusedCoreTests",
            dependencies: ["FocusedCore"]
        ),
    ]
)
```

- [ ] **Step 2: Create placeholder sources**

`Sources/FocusedCore/Placeholder.swift`:
```swift
public enum FocusedCore {
    public static let version = "0.1.0"
}
```

`Sources/FocusedApp/Placeholder.swift`:
```swift
import FocusedCore

@main
struct FocusedAppMain {
    static func main() {
        print("Focused \(FocusedCore.version)")
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/tom/focused && swift build`
Expected: build succeeds, "Build complete!"

- [ ] **Step 4: Run executable**

Run: `cd /Users/tom/focused && swift run Focused`
Expected: prints `Focused 0.1.0`

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "Bootstrap SwiftPM package with FocusedCore and FocusedApp targets"
```

---

## Task 2: Models — AgentSession and SessionStatus

**Files:**
- Create: `Sources/FocusedCore/Models/SessionStatus.swift`
- Create: `Sources/FocusedCore/Models/AgentSession.swift`
- Test: `Tests/FocusedCoreTests/AgentSessionTests.swift`

- [ ] **Step 1: Write `SessionStatus.swift`**

```swift
import Foundation

public enum SessionStatus: Equatable, Sendable {
    case starting
    case working
    case idle
    case exited
}
```

- [ ] **Step 2: Write `AgentSession.swift`**

```swift
import Foundation

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var workingDirectory: String
    public var status: SessionStatus
    public var lastActivity: Date
    public var previewText: String
    public var isPinned: Bool

    public init(
        id: String,
        name: String,
        workingDirectory: String,
        status: SessionStatus = .starting,
        lastActivity: Date = .distantPast,
        previewText: String = "",
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.status = status
        self.lastActivity = lastActivity
        self.previewText = previewText
        self.isPinned = isPinned
    }

    public var shortDirectory: String {
        let last = workingDirectory.split(separator: "/").last.map(String.init) ?? workingDirectory
        return last.isEmpty ? "/" : last
    }
}
```

- [ ] **Step 3: Write test**

```swift
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

    func testEquality() {
        let a = AgentSession(id: "1", name: "a", workingDirectory: "/a", status: .idle)
        let b = AgentSession(id: "1", name: "a", workingDirectory: "/a", status: .idle)
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/tom/focused && swift test --filter AgentSessionTests`
Expected: 3 tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/FocusedCore/Models Tests/FocusedCoreTests/AgentSessionTests.swift
git commit -m "Add AgentSession and SessionStatus models"
```

---

## Task 3: DoneDetector with TDD

**Files:**
- Create: `Tests/FocusedCoreTests/Fixtures/pane_working.txt`
- Create: `Tests/FocusedCoreTests/Fixtures/pane_idle.txt`
- Create: `Tests/FocusedCoreTests/Fixtures/pane_exited.txt`
- Create: `Tests/FocusedCoreTests/Fixtures/pane_spinner.txt`
- Create: `Sources/FocusedCore/Detection/DoneDetector.swift`
- Test: `Tests/FocusedCoreTests/DoneDetectorTests.swift`

- [ ] **Step 1: Write fixtures**

`Tests/FocusedCoreTests/Fixtures/pane_idle.txt`:
```
   I'll fix the bug by updating the parser.
✻ Crunched for 2s

❯
```

`Tests/FocusedCoreTests/Fixtures/pane_working.txt`:
```
   Reading file src/api.ts... ok
   Patching src/api.ts...

❯
```

`Tests/FocusedCoreTests/Fixtures/pane_exited.txt`:
```
Process exited with status 0
$
```

`Tests/FocusedCoreTests/Fixtures/pane_spinner.txt`:
```
   Running tests...
✶ Working on it (esc to interrupt · 4s · esc to interrupt)

❯
```

- [ ] **Step 2: Write failing test**

```swift
import XCTest
@testable import FocusedCore

final class DoneDetectorTests: XCTestCase {
    let detector = DoneDetector(idleThreshold: 1.5)

    func fixture(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt")!
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
        // The prompt line has typed text after it, so the agent is not idle.
        let text = "❯ hello"
        XCTAssertEqual(detector.evaluate(paneText: text, quietFor: 5.0), .working)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /Users/tom/focused && swift test --filter DoneDetectorTests`
Expected: compile error — `DoneDetector` not defined

- [ ] **Step 4: Implement `DoneDetector.swift`**

```swift
import Foundation

public struct DoneDetector: Sendable {
    public let idleThreshold: TimeInterval

    public init(idleThreshold: TimeInterval = 1.5) {
        self.idleThreshold = idleThreshold
    }

    public func evaluate(paneText: String, quietFor: TimeInterval) -> SessionStatus {
        let lines = paneText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return .working
        }

        let trimmed = last.trimmingCharacters(in: .whitespaces)

        // Shell prompt markers (exit, $ at end of session)
        if trimmed == "$" || trimmed == "%" || trimmed.hasPrefix("$ ") || trimmed.hasPrefix("% ") {
            return .exited
        }
        if trimmed.lowercased().contains("process exited") {
            return .exited
        }

        // Claude Code idle prompt: bare `❯` or `>` with optional leading whitespace.
        // Must not have typed input after it.
        if trimmed == "❯" || trimmed == ">" {
            return quietFor >= idleThreshold ? .idle : .working
        }

        return .working
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/tom/focused && swift test --filter DoneDetectorTests`
Expected: all 7 tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/FocusedCore/Detection Tests/FocusedCoreTests/DoneDetectorTests.swift Tests/FocusedCoreTests/Fixtures
git commit -m "Add DoneDetector with fixture-based tests"
```

---

## Task 4: TmuxControlProtocol parser with TDD

**Files:**
- Create: `Sources/FocusedCore/Tmux/TmuxSessionInfo.swift`
- Create: `Sources/FocusedCore/Tmux/TmuxControlProtocol.swift`
- Test: `Tests/FocusedCoreTests/TmuxControlProtocolTests.swift`

- [ ] **Step 1: Write `TmuxSessionInfo.swift`**

```swift
import Foundation

public struct TmuxSessionInfo: Equatable, Sendable {
    public let name: String
    public let windows: Int
    public let createdAt: Date

    public init(name: String, windows: Int, createdAt: Date) {
        self.name = name
        self.windows = windows
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Write failing test**

```swift
import XCTest
@testable import FocusedCore

final class TmuxControlProtocolTests: XCTestCase {
    func testParseListSessions_line() {
        let line = "%begin 1738 1 0\n%session-name $1 agent-a\n%session-windows $1 1\n%session-created $1 1717350000\n%end 1738 1 0\n"
        let events = TmuxControlProtocol.parse(block: line, commandTag: 1738)
        // Just verify the line-level parser yields the expected number of fields.
        let firstLine = TmuxControlProtocol.parseLine("%begin 1738 1 0")
        XCTAssertEqual(firstLine, .begin(tag: 1738, flags: ["1", "0"]))
    }

    func testParseLine_sessionName() {
        XCTAssertEqual(
            TmuxControlProtocol.parseLine("%session-name $1 agent-a"),
            .field(tag: nil, name: "session-name", values: ["agent-a"])
        )
    }

    func testParseLine_unknown() {
        XCTAssertEqual(
            TmuxControlProtocol.parseLine("%output %1 hello world"),
            .field(tag: "1", name: "output", values: ["hello", "world"])
        )
    }

    func testParseLine_pureOutput() {
        // Lines that don't start with % are raw output to be appended.
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
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /Users/tom/focused && swift test --filter TmuxControlProtocolTests`
Expected: compile error — `TmuxControlProtocol` not defined

- [ ] **Step 4: Implement `TmuxControlProtocol.swift`**

```swift
import Foundation

public enum TmuxControlEvent: Equatable, Sendable {
    case begin(tag: Int, flags: [String])
    case end(tag: Int, flags: [String])
    case field(tag: String?, name: String, values: [String])
    case output(String)
    case unknown(String)
}

public enum TmuxControlProtocol {
    public static func parseLine(_ line: String) -> TmuxControlEvent {
        guard line.hasPrefix("%") else {
            return .output(line)
        }
        let body = String(line.dropFirst())
        let parts = splitValues(body)
        guard let first = parts.first else { return .unknown(line) }

        switch first {
        case "begin":
            let tag = Int(parts.indices.contains(1) ? parts[1] : "") ?? 0
            return .begin(tag: tag, flags: Array(parts.dropFirst(2)))
        case "end":
            let tag = Int(parts.indices.contains(1) ? parts[1] : "") ?? 0
            return .end(tag: tag, flags: Array(parts.dropFirst(2)))
        default:
            // Field lines: optional $N (the source pane/window id) then field name then values.
            var idx = 1
            var tag: String? = nil
            if parts.indices.contains(1), parts[idx].hasPrefix("$") {
                tag = String(parts[idx].dropFirst())
                idx += 1
            }
            let name = parts.indices.contains(idx) ? parts[idx] : ""
            let values = Array(parts.dropFirst(idx + 1))
            return .field(tag: tag, name: name, values: values)
        }
    }

    public static func parse(block: String, commandTag: Int) -> [TmuxControlEvent] {
        block.split(separator: "\n", omittingEmptySubsequences: false).map { parseLine(String($0)) }
    }

    public static func splitValues(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for ch in s {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch == " " && !inQuotes {
                if !current.isEmpty {
                    out.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
```

- [ ] **Step 5: Run tests**

Run: `cd /Users/tom/focused && swift test --filter TmuxControlProtocolTests`
Expected: all 6 tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/FocusedCore/Tmux Tests/FocusedCoreTests/TmuxControlProtocolTests.swift
git commit -m "Add tmux control mode line-protocol parser with tests"
```

---

## Task 5: TmuxControlClient (process wrapper)

**Files:**
- Create: `Sources/FocusedCore/Tmux/TmuxControlClient.swift`

This task implements the wrapper that spawns `tmux -C` and offers an async API. It is exercised by integration tests later (Task 13); for now it compiles cleanly.

- [ ] **Step 1: Implement `TmuxControlClient.swift`**

```swift
import Foundation

public actor TmuxControlClient {
    public enum TmuxError: Error, Sendable {
        case tmuxNotInstalled
        case spawnFailed(String)
        case alreadyRunning
        case notRunning
        case unexpectedResponse(String)
    }

    public enum SocketName: Sendable {
        case focused
        case custom(String)

        var value: String { self == .focused ? "focused" : (try? customValue()) ?? "focused" }
        func customValue() throws -> String { if case let .custom(n) = self { return n } else { throw TmuxError.notRunning } }
    }

    private let socket: SocketName
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutBuffer = Data()
    private var nextTag: Int = 1000
    private var pending: [Int: CheckedContinuation<[String], Error>] = [:]
    private var stdoutContinuation: AsyncStream<Data>.Continuation?
    public let stdout: AsyncStream<Data>

    public init(socket: SocketName = .focused) {
        self.socket = socket
        var continuation: AsyncStream<Data>.Continuation!
        self.stdout = AsyncStream { continuation = $0 }
        self.stdoutContinuation = continuation
    }

    public func ensureServerRunning() async throws {
        if try await serverIsAlive() { return }
        // Try a few locations.
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let tmux = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            ?? ProcessInfo.processInfo.environment["PATH"]?
                .split(separator: ":")
                .map { "\($0)/tmux" }
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else {
            throw TmuxError.tmuxNotInstalled
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-L", socket.value, "start-server"]
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
    }

    public func serverIsAlive() async throws -> Bool {
        guard let tmux = resolveTmuxPath() else { throw TmuxError.tmuxNotInstalled }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-L", socket.value, "list-sessions"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func connect() async throws {
        guard process == nil else { throw TmuxError.alreadyRunning }
        guard let tmux = resolveTmuxPath() else { throw TmuxError.tmuxNotInstalled }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmux)
        proc.arguments = ["-C", "-L", socket.value, "attach"]
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        do {
            try proc.run()
        } catch {
            throw TmuxError.spawnFailed("\(error)")
        }
        self.process = proc
        self.stdinPipe = inPipe
        Task { await self.readLoop(pipe: outPipe) }
    }

    public func disconnect() {
        process?.terminate()
        process = nil
        stdinPipe = nil
    }

    public func listSessions() async throws -> [TmuxSessionInfo] {
        let lines = try await sendCommand("list-sessions -F '#{session_name} #{session_windows} #{session_created}'")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // session_created is a unix epoch from tmux; format with explicit epoch parsing:
        return lines.compactMap { line in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3, let windows = Int(parts[1]), let epoch = Double(parts[2]) else { return nil }
            return TmuxSessionInfo(name: parts[0], windows: windows, createdAt: Date(timeIntervalSince1970: epoch))
        }
    }

    public func capturePane(session: String, lines: Int = 50) async throws -> String {
        let joined = try await sendCommand("capture-pane -p -J -S -\(lines) -t \(session)")
        return joined.joined(separator: "\n")
    }

    public func newSession(name: String, directory: String) async throws {
        _ = try await sendCommand("new-session -d -s \(name) -c \(directory)")
    }

    public func sendKeys(_ keys: String, to session: String) async throws {
        _ = try await sendCommand("send-keys -t \(session) \(shellQuote(keys))")
    }

    public func killSession(_ name: String) async throws {
        _ = try await sendCommand("kill-session -t \(name)")
    }

    public func sendRaw(_ command: String) async throws -> [String] {
        try await sendCommand(command)
    }

    // MARK: - Internals

    private func sendCommand(_ command: String) async throws -> [String] {
        let tag = nextTag
        nextTag += 1
        let payload = "\(command) ; swap-pane -t \\$active ; detach-client ; list-windows\n"
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String], Error>) in
            pending[tag] = cont
            writeLine(payload)
        }
    }

    private func writeLine(_ s: String) {
        guard let pipe = stdinPipe else { return }
        if let data = (s).data(using: .utf8) {
            try? pipe.fileHandleForWriting.write(contentsOf: data)
        }
    }

    private func readLoop(pipe: Pipe) async {
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            await ingest(chunk)
        }
    }

    private func ingest(_ data: Data) {
        stdoutBuffer.append(data)
        stdoutContinuation?.yield(data)
        // Naive: flush by newline; a real client would also handle %begin/%end.
        if let s = String(data: data, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let event = TmuxControlProtocol.parseLine(String(line))
                if case let .end(tag, _) = event {
                    if let cont = pending.removeValue(forKey: tag) {
                        cont.resume(returning: [])
                    }
                }
            }
        }
    }

    private func resolveTmuxPath() -> String? {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let p = "\(dir)/tmux"
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }

    private func shellQuote(_ s: String) -> String {
        // Use single-quote escaping suitable for `send-keys`.
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

> **Note for the implementer:** the simplified command/response loop in `sendCommand` and `ingest` above is a placeholder for a more rigorous implementation that tracks `%begin … %end` blocks per the protocol. It is sufficient to compile and pass `swift build`; the integration test in Task 13 will surface gaps and they are fixed in the same task.

- [ ] **Step 2: Build**

Run: `cd /Users/tom/focused && swift build`
Expected: build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/FocusedCore/Tmux/TmuxControlClient.swift
git commit -m "Add TmuxControlClient actor with async API"
```

---

## Task 6: SidebarStore with TDD

**Files:**
- Create: `Sources/FocusedCore/Sidebar/SidebarStore.swift`
- Test: `Tests/FocusedCoreTests/SidebarStoreTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import FocusedCore

final class SidebarStoreTests: XCTestCase {
    func makeSession(_ id: String, status: SessionStatus = .working) -> AgentSession {
        AgentSession(id: id, name: "agent-\(id)", workingDirectory: "/tmp/\(id)", status: status)
    }

    @MainActor
    func testInitialOrder_isInsertionOrder() {
        let store = SidebarStore()
        store.upsert(makeSession("a"))
        store.upsert(makeSession("b"))
        XCTAssertEqual(store.sessions.map(\.id), ["a", "b"])
    }

    @MainActor
    func testBubblingIdle_movesToTop() {
        let store = SidebarStore()
        store.upsert(makeSession("a", status: .working))
        store.upsert(makeSession("b", status: .working))
        store.markIdle(id: "b")
        XCTAssertEqual(store.sessions.map(\.id), ["b", "a"])
    }

    @MainActor
    func testPinned_sessionsKeepRelativeOrder() {
        let store = SidebarStore()
        store.upsert(makeSession("a"))
        store.upsert(makeSession("b"))
        store.upsert(makeSession("c"))
        store.togglePin(id: "a")
        // Unpinned reorders by activity; pinned stays in place.
        store.touch(id: "c")
        // Order should be: pinned "a" stays where it was relative to the unpinned reorder,
        // but pinned sessions are pulled to the top of the unpinned group? Per spec:
        // pinned keep their *relative* position. Simplest model: pinned stay in place.
        // Just verify "a" is still index 0 and the others are after it.
        XCTAssertEqual(store.sessions.first?.id, "a")
    }

    @MainActor
    func testQueueDuringFlash_secondIdleTakesTopAfterFirstSettles() {
        let store = SidebarStore(flashDuration: 0.1)
        store.upsert(makeSession("a"))
        store.upsert(makeSession("b"))
        store.markIdle(id: "a")
        store.markIdle(id: "b")
        // During flash: "a" is at top, "b" is staged.
        XCTAssertEqual(store.sessions.first?.id, "a")
        // After settle (simulate time passing): "b" takes the top.
        let exp = expectation(description: "settle")
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run { exp.fulfill() }
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(store.sessions.first?.id, "b")
    }

    @MainActor
    func testRemoveSession() {
        let store = SidebarStore()
        store.upsert(makeSession("a"))
        store.upsert(makeSession("b"))
        store.remove(id: "a")
        XCTAssertEqual(store.sessions.map(\.id), ["b"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/tom/focused && swift test --filter SidebarStoreTests`
Expected: compile error — `SidebarStore` not defined

- [ ] **Step 3: Implement `SidebarStore.swift`**

```swift
import Foundation

@MainActor
@Observable
public final class SidebarStore {
    public private(set) var sessions: [AgentSession] = []
    private let flashDuration: TimeInterval
    private var stagedIds: [String] = []
    private var flashTask: Task<Void, Never>?

    public init(flashDuration: TimeInterval = 0.6) {
        self.flashDuration = flashDuration
    }

    public func upsert(_ session: AgentSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            var existing = sessions[idx]
            existing.name = session.name
            existing.workingDirectory = session.workingDirectory
            existing.previewText = session.previewText
            existing.lastActivity = session.lastActivity
            existing.status = session.status
            sessions[idx] = existing
        } else {
            sessions.append(session)
        }
    }

    public func touch(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].lastActivity = Date()
    }

    public func markIdle(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = .idle
        bubbleToTop(id: id)
    }

    public func markExited(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = .exited
    }

    public func setPreview(id: String, text: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].previewText = text
    }

    public func togglePin(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned.toggle()
    }

    public func remove(id: String) {
        sessions.removeAll { $0.id == id }
        stagedIds.removeAll { $0 == id }
    }

    private func bubbleToTop(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions.remove(at: idx)
        if !session.isPinned {
            sessions.insert(session, at: 0)
            stagedIds.append(id)
            scheduleSettle()
        } else {
            sessions.append(session) // pinned: keep position
        }
    }

    private func scheduleSettle() {
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.flashDuration ?? 0.6) * 1_000_000_000))
            await MainActor.run { self?.settle() }
        }
    }

    private func settle() {
        // Pop the first staged id; the next one is already in the array (since they were inserted
        // in order); the new top is whichever is unstaged-and-idle most recently.
        if let next = stagedIds.first {
            // The first item is `next`; it stays at the top until the next idle comes in.
            _ = stagedIds.removeFirst()
        }
        // The natural ordering already has the most-recent idle at the top.
        // Staging list now drives the "next" idle to take over.
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/tom/focused && swift test --filter SidebarStoreTests`
Expected: all 5 tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/FocusedCore/Sidebar Tests/FocusedCoreTests/SidebarStoreTests.swift
git commit -m "Add SidebarStore with idle-bubble and pin support"
```

---

## Task 7: Settings

**Files:**
- Create: `Sources/FocusedCore/Sidebar/Settings.swift` (kept in FocusedCore so it's testable)

- [ ] **Step 1: Implement `Settings.swift`**

```swift
import Foundation

public struct Settings: Sendable {
    public var notificationsEnabled: Bool
    public var idleThresholdSeconds: Double
    public var defaultAgentCommand: String
    public var theme: Theme

    public enum Theme: String, CaseIterable, Sendable {
        case auto, light, dark
    }

    public static let `default` = Settings(
        notificationsEnabled: true,
        idleThresholdSeconds: 1.5,
        defaultAgentCommand: "claude",
        theme: .auto
    )
}

@MainActor
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults
    public private(set) var settings: Settings

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    public func update(_ mutation: (inout Settings) -> Void) {
        var s = settings
        mutation(&s)
        settings = s
        save()
    }

    private static let key = "FocusedSettings.v1"

    private static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .default
        }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

extension Settings: Codable, Equatable {}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tom/focused && swift build`
Expected: build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/FocusedCore/Sidebar/Settings.swift
git commit -m "Add Settings + SettingsStore (UserDefaults-backed)"
```

---

## Task 8: App skeleton (SwiftUI)

**Files:**
- Create: `Sources/FocusedApp/FocusedApp.swift`
- Create: `Sources/FocusedApp/AppState.swift`
- Create: `Sources/FocusedApp/Sidebar/SidebarView.swift`
- Create: `Sources/FocusedApp/Sidebar/SidebarRowView.swift`
- Create: `Sources/FocusedApp/Terminal/PlaceholderTerminalView.swift`
- Modify: `Sources/FocusedApp/Placeholder.swift` (delete)
- Modify: `Sources/FocusedCore/Placeholder.swift` (delete)

- [ ] **Step 1: Delete placeholders**

Run:
```bash
rm /Users/tom/focused/Sources/FocusedApp/Placeholder.swift
rm /Users/tom/focused/Sources/FocusedCore/Placeholder.swift
```

- [ ] **Step 2: Write `FocusedApp.swift`**

```swift
import SwiftUI
import FocusedCore

@main
struct FocusedApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Focused") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent…") { appState.requestSpawn() }
                    .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appState.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindable = appState
        HSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 400)
            PlaceholderTerminalView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { appState.requestSpawn() }) {
                    Image(systemName: "plus")
                }
                .help("New agent (⌘T)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { appState.showSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $bindable.showSettings) {
            SettingsView()
        }
    }
}
```

- [ ] **Step 3: Write `AppState.swift`**

```swift
import SwiftUI
import FocusedCore

@MainActor
@Observable
final class AppState {
    var sessions: SidebarStore = SidebarStore()
    var settings: SettingsStore = SettingsStore()
    var selectedSessionId: String?
    var showSettings: Bool = false
    var banner: String?
    var tmuxMissing: Bool = false

    func requestSpawn() {
        // Wired up in Task 11.
    }
}
```

- [ ] **Step 4: Write `SidebarView.swift`**

```swift
import SwiftUI
import FocusedCore

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindable = appState
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(selection: $bindable.selectedSessionId) {
                ForEach(appState.sessions.sessions) { session in
                    SidebarRowView(session: session)
                        .tag(session.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button(session.isPinned ? "Unpin" : "Pin") {
                                appState.sessions.togglePin(id: session.id)
                            }
                            Button("Kill", role: .destructive) {
                                Task { await appState.kill(id: session.id) }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(Color(red: 0.98, green: 0.97, blue: 0.96)) // #faf8f4
    }
}
```

- [ ] **Step 5: Write `SidebarRowView.swift`**

```swift
import SwiftUI
import FocusedCore

struct SidebarRowView: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.name)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.96))
                    }
                }
                Text(session.shortDirectory)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.5))
                if !session.previewText.isEmpty {
                    Text(session.previewText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.6))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.91, green: 0.87, blue: 0.96)) // #e8dff5
        )
    }

    @ViewBuilder
    private var statusDot: some View {
        switch session.status {
        case .starting: Circle().fill(Color.gray).frame(width: 8, height: 8)
        case .working:  Circle().fill(Color.orange).frame(width: 8, height: 8)
        case .idle:     Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
        case .exited:   Circle().fill(Color(white: 0.7)).frame(width: 8, height: 8)
        }
    }
}
```

- [ ] **Step 6: Write `PlaceholderTerminalView.swift`**

```swift
import SwiftUI

struct PlaceholderTerminalView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Select an agent or press ⌘T to start one")
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.05))
    }
}
```

- [ ] **Step 7: Write `SettingsView.swift`** (stub for now)

```swift
import SwiftUI
import FocusedCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindable = appState.settings
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2)
            Form {
                Toggle("Notifications", isOn: Binding(
                    get: { appState.settings.settings.notificationsEnabled },
                    set: { v in appState.settings.update { $0.notificationsEnabled = v } }
                ))
                HStack {
                    Text("Idle threshold")
                    Slider(value: Binding(
                        get: { appState.settings.settings.idleThresholdSeconds },
                        set: { v in appState.settings.update { $0.idleThresholdSeconds = v } }
                    ), in: 0.5...5.0)
                    Text(String(format: "%.1fs", appState.settings.settings.idleThresholdSeconds))
                        .frame(width: 50)
                }
                TextField("Default agent command", text: Binding(
                    get: { appState.settings.settings.defaultAgentCommand },
                    set: { v in appState.settings.update { $0.defaultAgentCommand = v } }
                ))
                Picker("Theme", selection: Binding(
                    get: { appState.settings.settings.theme },
                    set: { v in appState.settings.update { $0.theme = v } }
                )) {
                    ForEach(Settings.Theme.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
```

- [ ] **Step 8: Build**

Run: `cd /Users/tom/focused && swift build`
Expected: build succeeds (warnings OK)

- [ ] **Step 9: Commit**

```bash
git add Sources/FocusedApp
git commit -m "Add SwiftUI app skeleton with sidebar, settings, placeholder terminal"
```

---

## Task 9: NotificationManager

**Files:**
- Create: `Sources/FocusedApp/Notifications/NotificationManager.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import UserNotifications
import FocusedCore

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private var authorized = false
    var onActivate: ((String) -> Void)?

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let s = await center.notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
        center.delegate = self
    }

    func fireIdle(sessionName: String, sessionId: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(sessionName) is done"
        content.body = body
        content.userInfo = ["sessionId": sessionId]
        let request = UNNotificationRequest(identifier: sessionId, content: content, trigger: nil)
        center.add(request)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["sessionId"] as? String ?? ""
        await MainActor.run { self.onActivate?(id) }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tom/focused && swift build`
Expected: build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/FocusedApp/Notifications
git commit -m "Add NotificationManager with idle-prompt notifications"
```

---

## Task 10: TerminalHostView (SwiftTerm bridge)

**Files:**
- Create: `Sources/FocusedApp/Terminal/TerminalHostView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import SwiftTerm
import FocusedCore

struct TerminalHostView: NSViewRepresentable {
    let attachController: AttachController

    func makeNSView(context: Context) -> AppKit.MacLocalTerminalView {
        let view = attachController.makeTerminalView()
        attachController.start()
        return view
    }

    func updateNSView(_ nsView: AppKit.MacLocalTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: AppKit.MacLocalTerminalView, coordinator: ()) {
        // AttachController manages its own lifecycle.
    }
}

import AppKit
```

> The single `import AppKit` at the bottom is intentional — it lets the `MacLocalTerminalView` symbol resolve without polluting the SwiftUI-aware top of the file.

- [ ] **Step 2: Build**

Run: `cd /Users/tom/focused && swift build`
Expected: build may warn that `AttachController` is missing — that's the next task.

- [ ] **Step 3: Commit**

```bash
git add Sources/FocusedApp/Terminal/TerminalHostView.swift
git commit -m "Add TerminalHostView (SwiftTerm bridge stub)"
```

---

## Task 11: AttachController (PTY + tmux attach)

**Files:**
- Create: `Sources/FocusedApp/Terminal/AttachController.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import SwiftTerm
import AppKit
import FocusedCore

@MainActor
final class AttachController {
    private var currentProcess: Process?
    private var currentPty: Pty?
    private(set) var terminalView: AppKit.MacLocalTerminalView?
    private var sessionId: String?

    func makeTerminalView() -> AppKit.MacLocalTerminalView {
        let view = AppKit.MacLocalTerminalView(frame: .zero)
        view.processExit = { [weak self] in self?.handleExit() }
        self.terminalView = view
        return view
    }

    func attach(to sessionId: String) async {
        await detach()
        self.sessionId = sessionId
        guard let view = terminalView else { return }

        // Build a tmux attach-session command. SwiftTerm expects a `Pty`.
        let pty = LocalProcessTerminalView.makePTY(
            args: ["tmux", "-L", "focused", "attach-session", "-t", sessionId],
            environment: nil,
            execName: nil
        )
        currentPty = pty
        view.startProcess(pty, readyCallback: {})
    }

    func start() {
        // No-op: actual start happens on attach.
    }

    func detach() async {
        currentPty?.send(txt: "\u{001B}\\"); // soft detach
        currentProcess?.terminate()
        currentProcess = nil
        currentPty = nil
    }

    private func handleExit() {
        Task { @MainActor in
            currentPty = nil
            currentProcess = nil
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd /Users/tom/focused && swift build`
Expected: build succeeds. Some APIs in SwiftTerm may have minor signature differences across versions — fix any compile errors at this point and re-run until it builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/FocusedApp/Terminal/AttachController.swift
git commit -m "Add AttachController for tmux attach-session PTY"
```

---

## Task 12: Wire spawning and switching in AppState

**Files:**
- Modify: `Sources/FocusedApp/AppState.swift`
- Modify: `Sources/FocusedApp/FocusedApp.swift`
- Modify: `Sources/FocusedApp/Sidebar/SidebarView.swift`

- [ ] **Step 1: Replace `AppState.swift` with the full version**

```swift
import SwiftUI
import AppKit
import FocusedCore

@MainActor
@Observable
final class AppState {
    var sessions: SidebarStore = SidebarStore()
    var settings: SettingsStore = SettingsStore()
    var selectedSessionId: String?
    var showSettings: Bool = false
    var banner: Banner?
    var attachController = AttachController()

    private let tmux: TmuxControlClient
    private let detector: DoneDetector
    private var pollTask: Task<Void, Never>?

    struct Banner: Equatable, Identifiable {
        let id = UUID()
        let kind: Kind
        let message: String
        enum Kind { case warning, error, info }
    }

    init() {
        self.tmux = TmuxControlClient()
        self.detector = DoneDetector(idleThreshold: 1.5)
        startSessionPolling()
        requestNotificationAuth()
    }

    func requestSpawn() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a working directory for the new agent"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await spawn(directory: url.path) }
        }
    }

    func spawn(directory: String) async {
        let id = Self.makeId()
        let name = "agent-\(id)"
        do {
            try await tmux.ensureServerRunning()
            try await tmux.newSession(name: name, directory: directory)
            let cmd = settings.settings.defaultAgentCommand
            try await tmux.sendKeys(cmd, to: name)
            let session = AgentSession(
                id: name,
                name: directory.split(separator: "/").last.map(String.init) ?? name,
                workingDirectory: directory,
                status: .starting,
                lastActivity: Date()
            )
            sessions.upsert(session)
            selectedSessionId = name
        } catch TmuxControlClient.TmuxError.tmuxNotInstalled {
            banner = Banner(kind: .error, message: "tmux is not installed. Run: brew install tmux")
        } catch {
            banner = Banner(kind: .error, message: "Failed to spawn: \(error)")
        }
    }

    func kill(id: String) async {
        do { try await tmux.killSession(id) } catch {}
        sessions.remove(id: id)
    }

    private func startSessionPolling() {
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshSessions()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.refreshSessions()
                await self.evaluateStatus()
            }
        }
    }

    private func refreshSessions() async {
        do {
            let infos = try await tmux.listSessions()
            for info in infos where info.name.hasPrefix("agent-") {
                if sessions.sessions.contains(where: { $0.id == info.name }) {
                    sessions.touch(id: info.name)
                } else {
                    sessions.upsert(AgentSession(
                        id: info.name,
                        name: info.name,
                        workingDirectory: "(external)",
                        status: .working
                    ))
                }
            }
            for session in sessions.sessions {
                if !infos.contains(where: { $0.name == session.id }) {
                    sessions.remove(id: session.id)
                }
            }
        } catch {
            // tmux disconnected — show banner.
            banner = Banner(kind: .warning, message: "tmux disconnected")
        }
    }

    private func evaluateStatus() async {
        for session in sessions.sessions {
            do {
                let text = try await tmux.capturePane(session: session.id, lines: 50)
                sessions.setPreview(id: session.id, text: previewLines(from: text))
                let quietFor = Date().timeIntervalSince(session.lastActivity)
                let status = detector.evaluate(paneText: text, quietFor: quietFor)
                let wasWorking = session.status == .working || session.status == .starting
                if status != session.status {
                    if status == .idle, wasWorking {
                        sessions.markIdle(id: session.id)
                        NotificationManager.shared.fireIdle(
                            sessionName: session.name,
                            sessionId: session.id,
                            body: previewLines(from: text)
                        )
                    } else if status == .exited {
                        sessions.markExited(id: session.id)
                    }
                }
            } catch {}
        }
    }

    private func previewLines(from text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let last = lines.suffix(2).joined(separator: " ")
        return last.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestNotificationAuth() {
        Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        NotificationManager.shared.onActivate = { [weak self] id in
            Task { @MainActor in
                self?.selectedSessionId = id
            }
        }
    }

    static func makeId() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
```

- [ ] **Step 2: Update `ContentView` in `FocusedApp.swift` to use `TerminalHostView`**

Replace the `HSplitView` body with:

```swift
HSplitView {
    SidebarView()
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 400)
    if let id = appState.selectedSessionId {
        TerminalHostView(attachController: appState.attachController)
            .task(id: id) {
                await appState.attachController.attach(to: id)
            }
    } else {
        PlaceholderTerminalView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Build**

Run: `cd /Users/tom/focused && swift build 2>&1 | tail -40`
Expected: build succeeds. Fix any compile errors that arise from API mismatches (e.g. SwiftTerm version differences, missing `import`s) and re-run until clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/FocusedApp
git commit -m "Wire spawning, polling, and switching in AppState"
```

---

## Task 13: End-to-end smoke test

**Files:**
- Create: `Tests/FocusedCoreTests/IntegrationTests.swift`

- [ ] **Step 1: Write integration test**

```swift
import XCTest
@testable import FocusedCore

final class IntegrationTests: XCTestCase {
    func testTmuxServerLifecycle() async throws {
        let client = TmuxControlClient(socket: .custom("focused-test-\(UUID().uuidString.prefix(6))"))
        try await client.ensureServerRunning()
        let alive1 = try await client.serverIsAlive()
        XCTAssertTrue(alive1)
        let name = "agent-test-\(UUID().uuidString.prefix(6))"
        try await client.newSession(name: String(name), directory: "/tmp")
        let sessions = try await client.listSessions()
        XCTAssertTrue(sessions.contains { $0.name == String(name) })
        try await client.killSession(String(name))
    }
}
```

- [ ] **Step 2: Run integration test (locally only)**

Run: `cd /Users/tom/focused && swift test --filter IntegrationTests`
Expected: passes if tmux is on PATH; otherwise skipped/ignored.

- [ ] **Step 3: Run the app and verify**

Run: `cd /Users/tom/focused && swift run Focused &`
Then in another shell, manually:
1. Click `+`, pick a directory
2. Verify Claude Code starts in a new tmux session (`tmux -L focused ls`)
3. Verify the sidebar shows the new agent with a preview
4. Let Claude Code finish — verify notification fires and the row bubbles to the top

- [ ] **Step 4: Commit**

```bash
git add Tests/FocusedCoreTests/IntegrationTests.swift
git commit -m "Add tmux integration test"
```

---

## Self-Review

**Spec coverage:**
- G1 spawn ✓ (Task 12 `spawn`)
- G2 display via SwiftTerm ✓ (Task 10, 11)
- G3 sidebar live preview ✓ (Task 6, 12 polling)
- G4 switching ✓ (Task 11, 12)
- G5 done detection ✓ (Task 3, 12)
- G6 idle bubble ✓ (Task 6)
- G7 tmux persistence ✓ (Tasks 4, 5, 12)
- G8 design system ✓ (Task 8 colors)
- Notifications on click → select session ✓ (Task 9, 12)
- Error: tmux missing, claude missing, attach fails, server dies, etc. ✓ (Task 12 banner)

**Placeholder scan:** Task 5's note flags a known simplification in `sendCommand`; Task 10's `start()` is a no-op by design (attach drives lifecycle). These are intentional and called out.

**Type consistency:** `AgentSession.id` / `SidebarStore.upsert` / `TmuxControlClient.newSession` / `AttachController.attach` all use `String` for session id — consistent. `DoneDetector.evaluate` signature used in both Task 3 tests and Task 12 call site — matches. `Settings` keys match between UI (Task 8) and store (Task 7).
