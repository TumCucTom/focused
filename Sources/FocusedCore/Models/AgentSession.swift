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
