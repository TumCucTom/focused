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

        // Shell prompt markers (returned to shell after exit)
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
