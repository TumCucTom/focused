import Foundation

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var workingDirectory: String
    public var status: SessionStatus
    public var lastActivity: Date
    public var previewText: String
    public var isPinned: Bool
    public let spawnedAt: Date

    public init(
        id: String,
        name: String,
        workingDirectory: String,
        status: SessionStatus = .starting,
        lastActivity: Date = .distantPast,
        previewText: String = "",
        isPinned: Bool = false,
        spawnedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.status = status
        self.lastActivity = lastActivity
        self.previewText = previewText
        self.isPinned = isPinned
        self.spawnedAt = spawnedAt
    }

    public var shortDirectory: String {
        let last = workingDirectory.split(separator: "/").last.map(String.init) ?? workingDirectory
        return last.isEmpty ? "/" : last
    }

    public func displayName(title: String?, command: String?) -> String {
        let folder = shortDirectory
        // Prefer the pane title (set by the running app via OSC 0/2 — for
        // Claude Code this is the current task). Fall back to the command
        // name (e.g. "zsh") for bare shells with no meaningful title.
        let label = trimmed(title) ?? trimmed(command)
        guard let label else { return folder }
        return "\(folder) — \(label)"
    }

    private func trimmed(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
