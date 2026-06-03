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
    public var idleSince: Date?
    public var workingSince: Date?
    public var gitBranch: String?

    public init(
        id: String,
        name: String,
        workingDirectory: String,
        status: SessionStatus = .starting,
        lastActivity: Date = .distantPast,
        previewText: String = "",
        isPinned: Bool = false,
        spawnedAt: Date = Date(),
        idleSince: Date? = nil,
        workingSince: Date? = nil,
        gitBranch: String? = nil
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.status = status
        self.lastActivity = lastActivity
        self.previewText = previewText
        self.isPinned = isPinned
        self.spawnedAt = spawnedAt
        self.idleSince = idleSince
        self.workingSince = workingSince
        self.gitBranch = gitBranch
    }

    public var shortDirectory: String {
        let last = workingDirectory.split(separator: "/").last.map(String.init) ?? workingDirectory
        return last.isEmpty ? "/" : last
    }

    public func displayName(title: String?, command: String?) -> String {
        let folder = shortDirectory
        let label = trimmed(title) ?? trimmed(command)
        guard let label else { return folder }
        return "\(folder) — \(label)"
    }

    /// Human-readable duration since the session entered its current status.
    public func statusDuration(now: Date = Date()) -> String? {
        switch status {
        case .idle: return idleSince.map { Self.shortFormat(now.timeIntervalSince($0)) }
        case .working, .starting: return workingSince.map { Self.shortFormat(now.timeIntervalSince($0)) }
        case .exited: return nil
        }
    }

    public static func shortFormat(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rem = m % 60
        if rem == 0 { return "\(h)h" }
        return "\(h)h\(rem)m"
    }

    private func trimmed(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
