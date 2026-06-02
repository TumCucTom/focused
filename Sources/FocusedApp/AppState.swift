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
    var attachController = AttachController()

    private let tmux: TmuxControlClient
    private var detector: DoneDetector
    private var pollTask: Task<Void, Never>?

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
                await self.evaluateStatus()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func requestSpawn() {
        guard !tmuxMissing else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a working directory for the new agent"
        panel.prompt = "Spawn"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await spawn(directory: url.path) }
        }
    }

    func spawn(directory: String) async {
        let id = Self.makeId()
        let name = "agent-\(id)"
        do {
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
        } catch {
            banner = Banner(kind: .error, message: "Failed to spawn: \(error)")
        }
    }

    func kill(id: String) async {
        try? await tmux.killSession(id)
        sessions.remove(id: id)
        if selectedSessionId == id { selectedSessionId = nil }
    }

    private func refreshSessions() async {
        do {
            let infos = try await tmux.listSessions()
            let agentInfos = infos.filter { $0.name.hasPrefix("agent-") }
            let known = Set(sessions.sessions.map(\.id))
            for info in agentInfos {
                if known.contains(info.name) {
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
            let currentNames = Set(agentInfos.map(\.name))
            for id in sessions.sessions.map(\.id) where !currentNames.contains(id) {
                sessions.remove(id: id)
                if selectedSessionId == id { selectedSessionId = nil }
            }
        } catch {
            banner = Banner(kind: .warning, message: "tmux disconnected")
        }
    }

    private func evaluateStatus() async {
        for session in sessions.sessions {
            do {
                let text = try await tmux.capturePane(session: session.id, lines: 50)
                let preview = previewLines(from: text)
                sessions.setPreview(id: session.id, text: preview)
                let quietFor = Date().timeIntervalSince(session.lastActivity)
                let status = detector.evaluate(paneText: text, quietFor: quietFor)
                if status == session.status { continue }
                let wasActive = session.status == .working || session.status == .starting
                if status == .idle, wasActive {
                    sessions.markIdle(id: session.id)
                    NotificationManager.shared.fireIdle(
                        sessionName: session.name,
                        sessionId: session.id,
                        body: preview
                    )
                } else if status == .exited {
                    sessions.markExited(id: session.id)
                }
            } catch {
                continue
            }
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
