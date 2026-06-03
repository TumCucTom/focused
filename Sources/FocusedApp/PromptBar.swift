import SwiftUI
import AppKit
import FocusedCore

struct PromptBar: View {
    @Environment(AppState.self) private var appState
    @State private var text: String = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: promptIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(promptColor)
            TextField(promptPlaceholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12).monospaced())
                .focused($focused)
                .onSubmit { submit() }
                .onKeyPress(.upArrow) {
                    navigateHistory(direction: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateHistory(direction: 1)
                    return .handled
                }
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.6))
                }
                .buttonStyle(.plain)
            }
            Button(action: submit) {
                Text(broadcast ? "Send All" : "Send")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(canSend ? Color.accentColor : Color(white: 0.7))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .onAppear { focused = true }
    }

    private var broadcast: Bool {
        appState.settings.settings.broadcastMode
    }

    private var promptIcon: String {
        broadcast ? "antenna.radiowaves.left.and.right" : "arrow.up.circle.fill"
    }

    private var promptColor: Color {
        broadcast ? Color(red: 1.0, green: 0.48, blue: 0.10) : Color.accentColor
    }

    private var promptPlaceholder: String {
        if broadcast { return "Broadcast to all working agents…" }
        if let id = appState.selectedSessionId { return "Send to \(displayName(for: id))…" }
        return "Select an agent first"
    }

    private var canSend: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if broadcast { return !appState.sessions.sessions.isEmpty }
        return appState.selectedSessionId != nil
    }

    private func displayName(for id: String) -> String {
        appState.sessions.sessions.first(where: { $0.id == id })?.name ?? id
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history.append(trimmed)
        if history.count > 50 { history = Array(history.suffix(50)) }
        historyIndex = nil
        text = ""

        if broadcast {
            Task {
                for session in appState.sessions.sessions where session.status != .exited {
                    try? await appState.sendToSession(id: session.id, text: trimmed)
                }
            }
        } else if let id = appState.selectedSessionId {
            Task { try? await appState.sendToSession(id: id, text: trimmed) }
        }
    }

    private func navigateHistory(direction: Int) {
        guard !history.isEmpty else { return }
        let next: Int
        if let idx = historyIndex {
            next = idx + direction
        } else {
            next = direction > 0 ? history.count : history.count - 1
        }
        guard next >= 0, next < history.count else { return }
        historyIndex = next
        text = history[next]
    }
}
