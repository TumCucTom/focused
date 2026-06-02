import SwiftUI
import FocusedCore

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindable = appState
        VStack(alignment: .leading, spacing: 0) {
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

            if appState.sessions.sessions.isEmpty {
                emptyState
            } else {
                List(selection: $bindable.selectedSessionId) {
                    ForEach(appState.sessions.sessions) { session in
                        SidebarRowView(session: session)
                            .tag(session.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .contextMenu {
                                Button(session.isPinned ? "Unpin" : "Pin") {
                                    appState.sessions.togglePin(id: session.id)
                                }
                                Button("Kill", role: .destructive) {
                                    Task { await appState.kill(id: session.id) }
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(red: 0.98, green: 0.97, blue: 0.96))
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
