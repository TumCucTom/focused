import SwiftUI
import FocusedCore

@main
struct FocusedApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Focused") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent…") { appState.requestSpawn() }
                    .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appState.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindable = appState
        HSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 400)
            mainArea
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { appState.requestSpawn() }) {
                    Image(systemName: "plus")
                }
                .help("New agent (⌘T)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: { appState.showSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $bindable.showSettings) {
            SettingsView()
        }
        .overlay(alignment: .top) {
            if let banner = appState.banner {
                BannerView(banner: banner) { appState.banner = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.banner)
    }

    @ViewBuilder
    private var mainArea: some View {
        if appState.tmuxMissing {
            EmptyStateBanner(
                title: "tmux not installed",
                message: "Focused uses tmux under the hood. Install it with Homebrew:",
                command: "brew install tmux"
            )
        } else if let id = appState.selectedSessionId,
                  appState.sessions.sessions.contains(where: { $0.id == id }) {
            PlaceholderTerminalView(sessionName: appState.sessions.sessions.first(where: { $0.id == id })?.name)
        } else {
            PlaceholderTerminalView(sessionName: nil)
        }
    }
}
