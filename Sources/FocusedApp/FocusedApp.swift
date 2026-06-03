import SwiftUI
import AppKit
import FocusedCore

@main
struct FocusedApp: App {
    @State private var appState = AppState()
    @State private var sidebarWidth: CGFloat = SidebarWidth.load()

    var body: some Scene {
        WindowGroup("Focused") {
            ContentView(sidebarWidth: $sidebarWidth)
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

enum SidebarWidth {
    private static let key = "FocusedSidebarWidth.v1"
    private static let `default`: CGFloat = 260
    private static let min: CGFloat = 180
    private static let max: CGFloat = 800

    static func load() -> CGFloat {
        let raw = UserDefaults.standard.double(forKey: key)
        guard raw > 0 else { return `default` }
        return min ... max ~= CGFloat(raw) ? CGFloat(raw) : `default`
    }

    static func save(_ value: CGFloat) {
        UserDefaults.standard.set(Double(value), forKey: key)
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Binding var sidebarWidth: CGFloat

    var body: some View {
        @Bindable var bindable = appState
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)
            SidebarDivider(width: $sidebarWidth)
            mainArea
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { appState.requestSpawn() }) {
                    Image(systemName: "plus")
                }
                .help("New shell in current directory (⌘T)")

                Menu {
                    Button("Spawn Claude Agent…") { appState.requestSpawnAgent() }
                    Divider()
                    if !appState.settings.settings.recentDirectories.isEmpty {
                        Menu("Recent Directories") {
                            ForEach(appState.settings.settings.recentDirectories, id: \.self) { dir in
                                Button(dir.split(separator: "/").last.map(String.init) ?? dir) {
                                    appState.requestSpawnInRecentDirectory(dir)
                                }
                            }
                        }
                        Divider()
                    }
                    Button("Pick Directory…") { appState.requestSpawnInDirectory() }
                    Button("Custom Command…") { appState.requestSpawnWithCommand() }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .help("More spawn options")
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
        .sheet(isPresented: $bindable.showSpawnPicker) {
            SpawnPickerView { dir in
                Task { await appState.spawn(directory: dir, command: nil) }
            }
        }
        .overlay(alignment: .top) {
            if let banner = appState.banner {
                BannerView(banner: banner) { appState.banner = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.banner)
        .onAppear { appState.applyAppearance() }
        .onChange(of: appState.settings.settings.theme) { _, _ in
            appState.applyAppearance()
        }
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
            TerminalHostView(
                attachController: appState.attachController,
                sessionId: id
            )
        } else {
            PlaceholderTerminalView(sessionName: nil)
        }
    }
}

struct SidebarDivider: View {
    @Binding var width: CGFloat
    @State private var hovering = false
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Rectangle()
                .fill(Color.accentColor.opacity(hovering ? 0.6 : 0))
                .frame(width: 3)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onChange(of: hovering) { _, isHovering in
            if isHovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }
                    let proposed = (dragStartWidth ?? width) + value.translation.width
                    width = SidebarWidth.clamp(proposed)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    SidebarWidth.save(width)
                }
        )
    }
}
