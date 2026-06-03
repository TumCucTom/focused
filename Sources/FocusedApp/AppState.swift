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
    var tmuxMissing: Bool = false
    var showSpawnPicker: Bool = false
    var attachController = AttachController()

    private let tmux: TmuxControlClient
    private var detector: DoneDetector
    private var pollTask: Task<Void, Never>?
    private var lastPaneTail: [String: String] = [:]
    private var lastGitFetch: [String: Date] = [:]
    private let gitFetchInterval: TimeInterval = 10.0
    private let spawnGracePeriod: TimeInterval = 2.0

    func currentAppearance() -> TerminalAppearance {
        switch settings.settings.theme {
        case .light: return .basic
        case .dark: return .pro
        case .auto:
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return .pro
            }
            return .basic
        }
    }

    func applyAppearance() {
        attachController.apply(appearance: currentAppearance())
    }

    struct Banner: Equatable, Identifiable {
        let id = UUID()
        let kind: Kind
        let message: String
        enum Kind: String { case warning, error, info }
    }

    init() {
        let tmux = TmuxControlClient()
        self.tmux = tmux
        self.detector = DoneDetector(idleThreshold: 1.5)
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    private func bootstrap() async {
        do {
            try await tmux.ensureServerRunning()
        } catch TmuxControlClient.TmuxError.tmuxNotInstalled {
            tmuxMissing = true
            return
        } catch {
            banner = Banner(kind: .error, message: "tmux error: \(error)")
            return
        }
        detector = DoneDetector(idleThreshold: settings.settings.idleThresholdSeconds)
        requestNotificationAuth()
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshSessions()
                await self.refreshNames()
                await self.refreshGitBranches()
                await self.evaluateStatus()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func requestSpawn() {
        guard !tmuxMissing else { return }
        let directory = defaultSpawnDirectory()
        Task { await spawn(directory: directory, command: nil) }
    }

    func requestSpawnInDirectory() {
        guard !tmuxMissing else { return }
        showSpawnPicker = true
    }

    func requestSpawnWithCommand() {
        guard !tmuxMissing else { return }
        let alert = NSAlert()
        alert.messageText = "Run a custom command"
        alert.informativeText = "This command will be sent to the new tmux session after it starts."
        alert.addButton(withTitle: "Spawn")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(string: settings.settings.defaultAgentCommand)
        input.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = input
        if alert.runModal() == .alertFirstButtonReturn {
            let cmd = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { return }
            let directory = defaultSpawnDirectory()
            Task { await spawn(directory: directory, command: cmd) }
        }
    }

    func requestSpawnAgent() {
        guard !tmuxMissing else { return }
        let directory = defaultSpawnDirectory()
        let cmd = settings.settings.defaultAgentCommand
        Task { await spawn(directory: directory, command: cmd) }
    }

    private func defaultSpawnDirectory() -> String {
        if let id = selectedSessionId,
           let session = sessions.sessions.first(where: { $0.id == id }),
           session.workingDirectory != "(external)" {
            return session.workingDirectory
        }
        return NSHomeDirectory()
    }

    func spawn(directory: String, command: String? = nil) async {
        let id = Self.makeId()
        let name = "agent-\(id)"
        do {
            try await tmux.newSession(name: name, directory: directory)
            if let command, !command.isEmpty {
                try await tmux.sendKeys(command, to: name)
            }
            let session = AgentSession(
                id: name,
                name: directory.split(separator: "/").last.map(String.init) ?? name,
                workingDirectory: directory,
                status: .starting,
                lastActivity: Date()
            )
            sessions.upsert(session)
            selectedSessionId = name
            recordRecentDirectory(directory)
        } catch {
            banner = Banner(kind: .error, message: "Failed to spawn: \(error)")
        }
    }

    private func recordRecentDirectory(_ directory: String) {
        settings.update { s in
            var recents = s.recentDirectories.filter { $0 != directory }
            recents.insert(directory, at: 0)
            if recents.count > 8 { recents = Array(recents.prefix(8)) }
            s.recentDirectories = recents
        }
    }

    func requestSpawnInRecentDirectory(_ directory: String) {
        guard !tmuxMissing else { return }
        Task { await spawn(directory: directory, command: nil) }
    }

    func kill(id: String) async {
        try? await tmux.killSession(id)
        sessions.remove(id: id)
        if selectedSessionId == id { selectedSessionId = nil }
    }

    /// Re-send the default agent command to the session. Works for sessions
    /// whose shell is still alive (i.e. Claude exited back to a prompt).
    /// For sessions where the shell itself died, the user should kill + respawn.
    func restart(id: String) async {
        let command = settings.settings.defaultAgentCommand
        do {
            try await tmux.sendKeys(command, to: id)
            sessions.setStatus(id: id, status: .working)
        } catch {
            banner = Banner(kind: .error, message: "Restart failed: \(error)")
        }
    }

    /// Send literal text to a session's pane and press Enter.
    /// Used by the inline prompt bar; for `Restart` we just re-send the command.
    func sendToSession(id: String, text: String) async throws {
        try await tmux.sendKeys(text, to: id)
        sessions.touch(id: id)
    }

    private func refreshSessions() async {
        do {
            let infos = try await tmux.listSessions()
            let agentInfos = infos.filter { $0.name.hasPrefix("agent-") }
            let known = Set(sessions.sessions.map(\.id))
            for info in agentInfos where !known.contains(info.name) {
                sessions.upsert(AgentSession(
                    id: info.name,
                    name: info.name,
                    workingDirectory: "(external)",
                    status: .working
                ))
            }
            let currentNames = Set(agentInfos.map(\.name))
            for id in sessions.sessions.map(\.id) where !currentNames.contains(id) {
                lastPaneTail.removeValue(forKey: id)
                sessions.remove(id: id)
                if selectedSessionId == id { selectedSessionId = nil }
            }
        } catch {
            banner = Banner(kind: .warning, message: "tmux disconnected")
        }
    }

    private func refreshNames() async {
        for session in sessions.sessions {
            let title = await tmux.paneTitle(session: session.id)
            let command = await tmux.currentCommand(session: session.id)
            let newName = session.displayName(title: title, command: command)
            if newName != session.name {
                sessions.setName(id: session.id, name: newName)
            }
        }
    }

    private func refreshGitBranches() async {
        let now = Date()
        for session in sessions.sessions {
            let last = lastGitFetch[session.id] ?? .distantPast
            if now.timeIntervalSince(last) < gitFetchInterval { continue }
            lastGitFetch[session.id] = now
            let branch = GitBranch.currentBranch(in: session.workingDirectory)
            sessions.setGitBranch(id: session.id, branch: branch)
        }
    }

    private func evaluateStatus() async {
        for session in sessions.sessions {
            do {
                let text = try await tmux.capturePane(session: session.id, lines: 50)
                let tail = semanticTail(text)
                if let prior = lastPaneTail[session.id] {
                    if prior != tail {
                        sessions.touch(id: session.id)
                    }
                }
                lastPaneTail[session.id] = tail

                let preview = previewLines(from: text)
                sessions.setPreview(id: session.id, text: preview)
                let quietFor = Date().timeIntervalSince(session.lastActivity)
                let status = detector.evaluate(paneText: text, quietFor: quietFor)
                if status == session.status { continue }

                let prev = session.status
                handleStatusTransition(
                    id: session.id,
                    from: prev,
                    to: status,
                    preview: preview
                )
            } catch {
                continue
            }
        }
        applyAutoFollow()
    }

    private func handleStatusTransition(
        id: String,
        from prev: SessionStatus,
        to current: SessionStatus,
        preview: String
    ) {
        let autoFollow = settings.settings.autoFollowIdle
        if current == .idle, prev == .working || prev == .starting {
            sessions.markIdle(id: id)
            if settings.settings.notificationsEnabled {
                let name = sessions.sessions.first(where: { $0.id == id })?.name ?? id
                NotificationManager.shared.fireIdle(
                    sessionName: name,
                    sessionId: id,
                    body: preview
                )
            }
            if autoFollow, !isFreshlySpawned(id: id) {
                selectedSessionId = id
            }
        } else if prev == .idle, current != .idle {
            if current == .exited {
                sessions.markExited(id: id)
            } else {
                sessions.setStatus(id: id, status: current)
            }
            if autoFollow, selectedSessionId == id {
                if let next = nextIdleSession(excluding: id) {
                    selectedSessionId = next
                }
            }
        } else if current == .exited {
            sessions.markExited(id: id)
        } else {
            sessions.setStatus(id: id, status: current)
        }
    }

    private func applyAutoFollow() {
        guard settings.settings.autoFollowIdle else { return }
        if let id = selectedSessionId,
           let current = sessions.sessions.first(where: { $0.id == id }) {
            if isFreshlySpawned(id: id) { return }
            if current.status == .idle { return }
        }
        if let top = sessions.sessions.first(where: { $0.status == .idle }) {
            if selectedSessionId != top.id {
                selectedSessionId = top.id
            }
        }
    }

    private func isFreshlySpawned(id: String) -> Bool {
        guard let s = sessions.sessions.first(where: { $0.id == id }) else { return false }
        return Date().timeIntervalSince(s.spawnedAt) < spawnGracePeriod
    }

    private func nextIdleSession(excluding id: String) -> String? {
        sessions.sessions.first(where: { $0.status == .idle && $0.id != id })?.id
    }

    private func semanticTail(_ text: String, lines: Int = 3) -> String {
        let nonEmpty = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return nonEmpty.suffix(lines).joined(separator: "\n")
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
