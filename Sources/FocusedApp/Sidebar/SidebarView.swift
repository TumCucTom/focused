import SwiftUI
import FocusedCore

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    private var filteredSessions: [AgentSession] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.sessions.sessions }
        return appState.sessions.sessions.filter { s in
            s.name.lowercased().contains(q)
                || s.workingDirectory.lowercased().contains(q)
                || s.previewText.lowercased().contains(q)
        }
    }

    var body: some View {
        @Bindable var bindable = appState
        VStack(alignment: .leading, spacing: 0) {
            header
            if appState.sessions.sessions.isEmpty {
                emptyState
            } else {
                searchField
                sessionList(selection: $bindable.selectedSessionId)
            }
        }
        .background(Color(red: 0.98, green: 0.97, blue: 0.96))
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebarSearch)) { _ in
            searchFocused = true
        }
    }

    private var header: some View {
        HStack {
            Text("Agents")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .textCase(.uppercase)
                .tracking(0.15)
            Spacer()
            Text("\(appState.sessions.sessions.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.55))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.55))
            TextField("Filter", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.92))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    @ViewBuilder
    private func sessionList(selection: Binding<String?>) -> some View {
        let sessions = filteredSessions
        if sessions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        } else {
            List(selection: selection) {
                ForEach(sessions) { session in
                    SidebarRowView(session: session)
                        .tag(session.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                        .contextMenu { contextMenu(for: session) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func contextMenu(for session: AgentSession) -> some View {
        Button(session.isPinned ? "Unpin" : "Pin") {
            appState.sessions.togglePin(id: session.id)
        }
        Button("Restart") {
            Task { await appState.restart(id: session.id) }
        }
        Divider()
        Button("Copy `tmux attach` Command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("tmux -L focused attach -t \(session.id)", forType: .string)
        }
        Divider()
        Button("Kill", role: .destructive) {
            Task { await appState.kill(id: session.id) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No agents yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.35))
            Text("Press ⌘T or click + to spawn one.")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}
