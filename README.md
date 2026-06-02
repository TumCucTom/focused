# Focused

A native macOS app for running multiple Claude Code agents in parallel — one
window, one active agent, a sidebar of all the others.

## What it does

- **Spawn** a Claude Code agent in any directory with one click (`⌘T`).
- **Display** the active agent's terminal with full Terminal.app-equivalent
  behavior (resize, `Ctrl-C`, paste, ANSI colors) — the active view is a real
  `tmux attach-session` rendered by SwiftTerm.
- **Track** every agent in a sidebar with a live preview, status dot, and
  working directory.
- **Notify** when an agent goes idle (`❯` prompt + 1.5s of silence) via a macOS
  notification, and **bubble** the freshly-idle agent to the top of the
  sidebar. If two finish in the same flash window, the second queues and
  takes the top when the first settles.
- **Pick up** existing agents — anything already in the `tmux -L focused`
  server appears in the sidebar. You can also `tmux attach -t agent-<id>`
  from any terminal and the app keeps tracking it.

## Architecture

The app is a thin SwiftUI layer on top of **tmux**. All Claude Code agents
run as tmux sessions inside a private server launched with `tmux -L focused`.
tmux is the source of truth for session state; the app owns none of it.

```
SwiftUI chrome (sidebar, settings, banners)
   │
   ├─ TmuxControlClient  ──► tmux list-sessions, new-session, send-keys,
   │                        capture-pane, kill-session
   │
   ├─ SessionMonitor     ──► polls every 1s, runs DoneDetector per session,
   │                        emits idle/exited transitions
   │
   ├─ SidebarStore       ──► ordering, idle-bubble, pin, queue
   │
   └─ AttachController   ──► LocalProcessTerminalView bound to
                             `tmux attach-session -t <id>` (real PTY)
```

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6.0+
- [tmux](https://github.com/tmux/tmux) (`brew install tmux`)

## Build & run

```sh
swift build
swift run Focused
```

The app will request notification permission on first agent spawn.

## Test

```sh
swift test
```

34 tests cover models, the done detector, the sidebar state machine, the
tmux line-protocol parser, the tmux client (with real-tmux integration
tests), and the spawn→capture→kill pipeline.

## Spec & plan

- Design: `docs/superpowers/specs/2026-06-02-focused-terminal-app-design.md`
- Plan: `docs/superpowers/plans/2026-06-02-focused-terminal-app.md`

## Layout

```
Sources/
  FocusedCore/    library (testable)
    Models/       AgentSession, SessionStatus
    Tmux/         TmuxControlClient, TmuxControlProtocol, TmuxSessionInfo
    Detection/    DoneDetector
    Sidebar/      SidebarStore, Settings
  FocusedApp/     executable (SwiftUI)
    Sidebar/      SidebarView, SidebarRowView
    Terminal/     TerminalHostView, AttachController, PlaceholderTerminalView
    Notifications/ NotificationManager
    Settings/     SettingsView
    Banners/      BannerView, EmptyStateBanner
    FocusedApp.swift, AppState.swift

Tests/FocusedCoreTests/
  DoneDetectorTests, SidebarStoreTests, TmuxControlProtocolTests,
  AgentSessionTests, IntegrationTests, EndToEndPipelineTests
  Fixtures/   recorded pane snapshots
```
