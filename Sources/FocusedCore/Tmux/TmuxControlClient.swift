import Foundation

public actor TmuxControlClient {
    public enum TmuxError: Error, Sendable, Equatable {
        case tmuxNotInstalled
        case commandFailed(command: String, exitCode: Int32, stderr: String)
        case sessionNotFound(String)
    }

    public enum SocketName: Sendable, Equatable {
        case focused
        case custom(String)

        var value: String {
            switch self {
            case .focused: return "focused"
            case .custom(let name): return name
            }
        }
    }

    public let socket: SocketName

    public init(socket: SocketName = .focused) {
        self.socket = socket
    }

    // MARK: - Server lifecycle

    public func ensureServerRunning() async throws {
        if try await serverIsAlive() { return }
        _ = try await runRaw(args: ["-L", socket.value, "start-server"], throwOnError: false)
    }

    public func serverIsAlive() async throws -> Bool {
        // Reliable liveness check: tmux's commands return confusing exit codes
        // (info returns 0 even with no server, list-sessions returns 1 with no
        // sessions, has-session returns 1 if the session doesn't exist). The
        // ground truth is whether the socket file exists in the user's tmux dir.
        let uid = getuid()
        let path = "/private/tmp/tmux-\(uid)/\(socket.value)"
        return FileManager.default.fileExists(atPath: path)
    }

    public func restartServer() async throws {
        _ = try? await runRaw(args: ["-L", socket.value, "kill-server"], throwOnError: false)
        _ = try await runRaw(args: ["-L", socket.value, "start-server"], throwOnError: false)
    }

    // MARK: - Session queries

    public func listSessions() async throws -> [TmuxSessionInfo] {
        let format = "#{session_name} #{session_windows} #{session_created}"
        let result = try await runRaw(
            args: ["-L", socket.value, "list-sessions", "-F", format],
            throwOnError: false
        )
        guard result.exitCode == 0 else { return [] }
        return result.stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3,
                  let windows = Int(parts[1]),
                  let epoch = Double(parts[2]) else { return nil }
            return TmuxSessionInfo(
                name: parts[0],
                windows: windows,
                createdAt: Date(timeIntervalSince1970: epoch)
            )
        }
    }

    public func capturePane(session: String, lines: Int = 50) async throws -> String {
        let result = try await runRaw(
            args: ["-L", socket.value, "capture-pane", "-p", "-J", "-S", "-\(lines)", "-t", session],
            throwOnError: false
        )
        guard result.exitCode == 0 else { return "" }
        return result.stdout
    }

    public func sessionExists(_ name: String) async -> Bool {
        let result = try? await runRaw(
            args: ["-L", socket.value, "has-session", "-t", name],
            throwOnError: false
        )
        return result?.exitCode == 0
    }

    // MARK: - Session mutation

    public func newSession(name: String, directory: String) async throws {
        let result = try await runRaw(
            args: ["-L", socket.value, "new-session", "-d", "-s", name, "-c", directory],
            throwOnError: true
        )
        if result.exitCode != 0 {
            throw TmuxError.commandFailed(
                command: "new-session",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    public func sendKeys(_ keys: String, to session: String) async throws {
        let result = try await runRaw(
            args: ["-L", socket.value, "send-keys", "-t", session, keys, "Enter"],
            throwOnError: true
        )
        if result.exitCode != 0 {
            throw TmuxError.commandFailed(
                command: "send-keys",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    public func killSession(_ name: String) async throws {
        let result = try await runRaw(
            args: ["-L", socket.value, "kill-session", "-t", name],
            throwOnError: false
        )
        if result.exitCode != 0 {
            throw TmuxError.sessionNotFound(name)
        }
    }

    // MARK: - Internal: shell out to tmux

    struct CommandResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runRaw(args: [String], throwOnError: Bool) async throws -> CommandResult {
        guard let tmuxPath = resolveTmuxPath() else {
            throw TmuxError.tmuxNotInstalled
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw TmuxError.commandFailed(
                command: args.joined(separator: " "),
                exitCode: -1,
                stderr: "\(error)"
            )
        }
        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return CommandResult(exitCode: proc.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let p = "\(dir)/tmux"
                if FileManager.default.isExecutableFile(atPath: p) { return p }
            }
        }
        return nil
    }
}
