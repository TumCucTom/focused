import Foundation
import SwiftTerm
import AppKit
import FocusedCore

final class FocusedTerminalView: LocalProcessTerminalView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AttachController: NSObject, LocalProcessTerminalViewDelegate {
    private(set) var terminalView: LocalProcessTerminalView?
    private(set) var currentSession: String?
    private(set) var appearance: TerminalAppearance = .basic

    func makeTerminalView() -> LocalProcessTerminalView {
        let view = FocusedTerminalView(frame: .zero)
        view.processDelegate = self
        view.apply(appearance: appearance)
        self.terminalView = view
        return view
    }

    func apply(appearance: TerminalAppearance) {
        self.appearance = appearance
        terminalView?.apply(appearance: appearance)
    }

    func attach(to sessionId: String) {
        // Tear down any prior attach.
        detach()

        guard let view = terminalView else { return }

        let tmuxPath = resolveTmuxPath() ?? "/usr/bin/tmux"
        currentSession = sessionId
        view.startProcess(
            executable: tmuxPath,
            args: ["-L", "focused", "attach-session", "-t", sessionId],
            environment: nil
        )
    }

    func detach() {
        terminalView?.terminate()
        currentSession = nil
    }

    // MARK: - LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {}

    private func resolveTmuxPath() -> String? {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
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
