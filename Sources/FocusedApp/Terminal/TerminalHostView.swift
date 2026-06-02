import SwiftUI
import SwiftTerm
import FocusedCore

struct TerminalHostView: NSViewRepresentable {
    let attachController: AttachController
    let sessionId: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = attachController.terminalView ?? attachController.makeTerminalView()
        attachController.attach(to: sessionId)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if attachController.currentSession != sessionId {
            attachController.attach(to: sessionId)
        }
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // AttachController manages the lifecycle explicitly.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {}
}
