import Foundation

@MainActor
@Observable
public final class SidebarStore {
    public private(set) var sessions: [AgentSession] = []
    private let flashDuration: TimeInterval
    private var flashingId: String?
    private var stagedId: String?
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
            // Preserve pin and status: use togglePin / markIdle / markExited for those.
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
        let wasFlashing = (flashingId == id)
        sessions[idx].status = .idle
        if sessions[idx].isPinned { return }
        if wasFlashing { return }
        let session = sessions.remove(at: idx)
        insertIdle(session, id: id)
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
        if flashingId == id {
            flashingId = nil
            promoteStaged()
        }
        if stagedId == id { stagedId = nil }
    }

    private func insertIdle(_ session: AgentSession, id: String) {
        if flashingId == nil {
            // No active flash: this session becomes the current flash.
            // Pinned sessions block bubbling: insert just after the last pinned session.
            let insertAt: Int = {
                if let lastPinned = sessions.lastIndex(where: { $0.isPinned }) {
                    return lastPinned + 1
                }
                return 0
            }()
            sessions.insert(session, at: insertAt)
            flashingId = id
            scheduleFlashEnd()
        } else {
            // Active flash: stage this session just after the currently-flashing item
            // (or at 0 if the flashing item was somehow removed).
            let anchor = sessions.firstIndex(where: { $0.id == flashingId }) ?? -1
            let insertAt = max(0, min(anchor + 1, sessions.count))
            sessions.insert(session, at: insertAt)
            stagedId = id
        }
    }

    private func scheduleFlashEnd() {
        flashTask?.cancel()
        let duration = flashDuration
        let id = flashingId
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                guard let self, self.flashingId == id else { return }
                self.flashingId = nil
                self.promoteStaged()
            }
        }
    }

    private func promoteStaged() {
        guard let staged = stagedId,
              let stagedIdx = sessions.firstIndex(where: { $0.id == staged }) else {
            stagedId = nil
            return
        }
        let session = sessions.remove(at: stagedIdx)
        sessions.insert(session, at: 0)
        flashingId = staged
        stagedId = nil
        scheduleFlashEnd()
    }
}
