import SwiftUI
import AppKit
import FocusedCore

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var query: String = ""
    @State private var selectionIndex: Int = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { runHighlighted() }
                    .onChange(of: query) { _, _ in selectionIndex = 0 }
                Text("esc")
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.9)))
                    .foregroundStyle(Color(white: 0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if filteredActions.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(filteredActions.enumerated()), id: \.offset) { idx, action in
                            row(action: action, isSelected: idx == selectionIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectionIndex = idx
                                    runHighlighted()
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 520)
        .onKeyPress(.upArrow) {
            if !filteredActions.isEmpty {
                selectionIndex = (selectionIndex - 1 + filteredActions.count) % filteredActions.count
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !filteredActions.isEmpty {
                selectionIndex = (selectionIndex + 1) % filteredActions.count
            }
            return .handled
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onAppear { focused = true }
    }

    private func row(action: PaletteAction, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.45))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                if let detail = action.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            Spacer()
            if let key = action.shortcut {
                Text(key)
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.92)))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .padding(.horizontal, 6)
        )
    }

    private func runHighlighted() {
        guard !filteredActions.isEmpty else { return }
        let action = filteredActions[min(selectionIndex, filteredActions.count - 1)]
        dismiss()
        DispatchQueue.main.async { action.run() }
    }

    private var filteredActions: [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = allActions()
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || ($0.detail?.lowercased().contains(q) ?? false) }
    }

    private func allActions() -> [PaletteAction] {
        var actions: [PaletteAction] = [
            .init(icon: "plus.circle", title: "New Shell in Current Directory", detail: "Spawn a bare shell", shortcut: "⌘T") { appState.requestSpawn() },
            .init(icon: "person.fill", title: "Spawn Claude Agent", detail: "Run the default agent command") { appState.requestSpawnAgent() },
            .init(icon: "folder", title: "Pick Directory…", detail: "Choose a working directory") { appState.requestSpawnInDirectory() },
            .init(icon: "terminal", title: "Custom Command…", detail: "Spawn and send a one-off command") { appState.requestSpawnWithCommand() },
            .init(icon: "magnifyingglass", title: "Focus Sidebar Search", detail: "⌘F", shortcut: "⌘F") { NotificationCenter.default.post(name: .focusSidebarSearch, object: nil) },
            .init(icon: "gearshape", title: "Settings…", detail: nil, shortcut: "⌘,") { appState.showSettings = true },
            .init(icon: appState.settings.settings.broadcastMode ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                  title: appState.settings.settings.broadcastMode ? "Disable Broadcast Mode" : "Enable Broadcast Mode",
                  detail: "Send prompt to all working agents") {
                appState.settings.update { $0.broadcastMode.toggle() }
            },
            .init(icon: appState.settings.settings.showPromptBar ? "rectangle.bottomthird.inset.filled" : "rectangle",
                  title: appState.settings.settings.showPromptBar ? "Hide Prompt Bar" : "Show Prompt Bar",
                  detail: nil) {
                appState.settings.update { $0.showPromptBar.toggle() }
            },
            .init(icon: appState.settings.settings.theme == .dark ? "sun.max" : "moon",
                  title: "Switch to \(appState.settings.settings.theme == .dark ? "Light" : "Dark") Theme",
                  detail: nil) {
                appState.settings.update { s in s.theme = (s.theme == .dark) ? .light : .dark }
            },
        ]
        if let id = appState.selectedSessionId {
            let name = appState.sessions.sessions.first(where: { $0.id == id })?.name ?? id
            actions.append(.init(icon: "arrow.clockwise", title: "Restart \(name)", detail: "Re-send the default agent command") {
                Task { await appState.restart(id: id) }
            })
            actions.append(.init(icon: "xmark.circle", title: "Kill \(name)", detail: "Destroy the tmux session", role: .destructive) {
                Task { await appState.kill(id: id) }
            })
        }
        if let session = appState.sessions.sessions.first(where: { $0.id == appState.selectedSessionId }) {
            for s in appState.sessions.sessions.prefix(10) where s.id != session.id {
                actions.append(.init(icon: "rectangle.2.swap", title: "Switch to \(s.name)", detail: s.workingDirectory) {
                    appState.selectedSessionId = s.id
                })
            }
        } else {
            for s in appState.sessions.sessions.prefix(10) {
                actions.append(.init(icon: "rectangle.2.swap", title: "Switch to \(s.name)", detail: s.workingDirectory) {
                    appState.selectedSessionId = s.id
                })
            }
        }
        return actions
    }
}

struct PaletteAction: Identifiable {
    enum Role { case normal, destructive }
    let id = UUID()
    let icon: String
    let title: String
    let detail: String?
    var shortcut: String? = nil
    var role: Role = .normal
    let run: () -> Void
}

extension Notification.Name {
    static let focusSidebarSearch = Notification.Name("Focused.focusSidebarSearch")
}
