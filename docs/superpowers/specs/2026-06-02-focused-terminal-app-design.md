# Focused — Terminal App for Parallel Claude Code Agents

**Date:** 2026-06-02
**Status:** Draft (pending user review)
**Target platform:** macOS (native, SwiftUI)

## Problem

Running multiple Claude Code agents in parallel from the macOS Terminal app means juggling many windows, losing track of which agent finished, and context-switching by hand. The user wants a single-window app that:

- Renders one active agent's terminal full-size.
- Shows a scrollable sidebar of all agents, with a small live preview of each.
- Lets you click a sidebar item to swap the active view to that agent.
- Notifies you (macOS notification) when an agent goes idle.
- Bubbles freshly-idle agents to the top of the sidebar (with a queue if multiple finish in the same window).
- Lets the user attach to the same agents externally (`tmux attach -t agent-<id>`) without disrupting the app.

## Goals

- **G1** Spawn a new Claude Code agent in a chosen directory with one click.
- **G2** Display the active agent's terminal with full Terminal.app-equivalent behavior (resize, Ctrl-C, bracketed paste, ANSI colors).
- **G3** Show a live, scrollable sidebar of all agents with status, directory, and a 2–3 line preview of recent output.
- **G4** Switch the active agent by clicking a sidebar item, with a smooth visual transition.
- **G5** Detect the Claude Code idle prompt (`❯` at column 0) plus a short quiet period (default 1.5s) and fire a macOS notification.
- **G6** Reorder the sidebar so the most-recently-idle agent is at the top; if multiple finish in the flash window, they queue.
- **G7** Survive app quit and relaunch by using tmux as the source of truth — no app-side persistence needed.
- **G8** Match the project design system (warm cream chrome, Inter typography, purple/orange accents) per `/Users/tom/.claude/design/DESIGN.md`.

## Non-Goals (v1)

- Multi-window, tabs, workspaces, session groups.
- Input broadcasting to multiple sessions.
- Custom tmux config; we use tmux defaults.
- Custom terminal color themes (use Terminal.app defaults).
- Scrollback export, search, copy-mode UI.
- iOS / iPadOS companion.
- iCloud sync.
- Telemetry / analytics.
- A settings page beyond four toggles: notifications on/off, idle threshold, default agent command, theme.
- App-side persistence — tmux is the only source of truth.

## Architecture

### Process model

The app is a polished native UI sitting on top of **tmux**. All Claude Code agents run as tmux sessions inside a private tmux server launched with `-L focused`.

Three long-lived process relationships:

1. **Tmux server** (`tmux -L focused`) — owned by the user's login session, started on first app launch, persists across app quit/relaunch.
2. **Control-mode client** (`tmux -C -L focused`) — one child process, always running. Used for listing sessions, capturing pane text (sidebar previews + done-detector), spawning new sessions, sending spawn commands.
3. **Attach child** — at most one at a time, started as `tmux attach-session -t agent-<id>`. Owns a real PTY whose stdout feeds SwiftTerm and whose stdin receives SwiftTerm keystrokes. This is what gives us Terminal.app-equivalent behavior.

### Components

| Component | Responsibility |
|---|---|
| `TmuxControlClient` | Wraps the control-mode child. Owns the `tmux -C` line protocol. Async/await API: `listSessions()`, `capturePane(_:)`, `newSession(directory:)`, `killSession(_:)`, `sendKeys(_:to:)`. |
| `SessionMonitor` | Polls every 200ms for the active session and 1s for inactive ones. Owns the `AgentSession` state machine (`working` / `idle` / `exited` / `starting`). Calls `capturePane`, runs the done-detector, emits `SessionDidGoIdle` events. |
| `DoneDetector` | Pure function: `(paneText, lastChangeAt) -> SessionStatus`. Regex match on Claude Code's idle prompt plus quiet-period check. Unit-testable in isolation. |
| `AgentSession` | In-memory model: id, name, working directory, status, last activity timestamp, last preview text. Not persisted — rebuilt from tmux on launch. |
| `SidebarStore` | `@Observable` (Swift 6) store of `AgentSession`s in display order. Handles pin/unpin, idle-bubble, queue-during-flash. |
| `NotificationManager` | Wraps `UNUserNotificationCenter`. Requests permission on first spawn. Fires one notification per working→idle transition. Handles activation → bring app forward + select session. |
| `AttachController` | Manages the single attach child. `attach(to: sessionId)` kills the old child, spawns a new one, rebinds SwiftTerm's IO streams. |
| `TerminalHostView` | SwiftUI `NSViewRepresentable` wrapping SwiftTerm's `TerminalView`. Forwards keystrokes to `AttachController.input` and exposes a resize callback. |
| `SessionListView` | Sidebar UI per the design system (warm cream surface, Inter typography, 10–16px rounded corners, purple accent for selected, green flash on idle-bubble). |
| `Settings` | UserDefaults-backed. Four keys: `notificationsEnabled`, `idleThresholdSeconds`, `defaultAgentCommand`, `theme`. |

### Data flow

**Spawning**
1. User clicks `+` in toolbar.
2. `NSOpenPanel` (directories only) returns a path.
3. `TmuxControlClient.newSession(directory:)` → `tmux new-session -d -s agent-<shortId> -c <path>`.
4. `TmuxControlClient.sendKeys("claude", to: <shortId>)` + `\n`.
5. SessionMonitor sees the new session on the next poll, creates `AgentSession` in `starting` state, marks it as selected.
6. AttachController starts a new attach child for the new session; SwiftTerm rebinds.

**Active display**
- `attach-child.stdout` → SwiftTerm
- SwiftTerm keystrokes → `attach-child.stdin` → tmux pane → Claude Code's PTY

**Output fan-out**
- Claude Code writes → tmux pane → two consumers:
  1. attach-child stdout → SwiftTerm (live, frame-accurate)
  2. control-mode `capture-pane` (periodic) → sidebar preview + done detector

**Switching**
1. User clicks a sidebar row.
2. `AttachController.switch(to: sessionId)`:
   a. Soft-detach current: terminate the current attach child (SIGTERM, then SIGKILL after 200ms if needed). tmux holds the pane open for re-attach; the session's contents are preserved. (`Detach` here means disconnecting our local client from tmux, not killing the tmux session itself.)
   b. Spawn new attach child: `tmux attach-session -t <newId>` with a fresh PTY.
   c. Bind new child IO to SwiftTerm.
3. SwiftTerm redraws from new child's stdout. 80ms crossfade tween between views.

**Done detection (per session, every poll cycle)**
1. `capture-pane -p -J -S -50` — last ~50 lines, joined if wrapped.
2. Take last non-empty line.
3. Regex `^\s*[❯>]\s*$` (with a small allowlist of common variants).
4. If matched AND `now - lastChangeAt > idleThreshold`: emit `SessionDidGoIdle`.
5. On the transition edge (working→idle), `NotificationManager.fire` and `SidebarStore.bubbleToTop`.

**Lifecycle**
- **App quit:** kill control-mode child + attach child. **Tmux server keeps running.** Agents keep working.
- **App relaunch:** control mode reconnects, calls `listSessions()`, repopulates the sidebar.
- **Tmux server death:** control-mode pipe errors out. App shows a sticky banner "tmux disconnected" with a "Restart tmux" button (kills stale server, relaunches via `tmux -L focused start-server`).

## UI / Layout

Single window, no tabs. Toolbar at top, split content (terminal | sidebar), responsive.

```
┌─────────────────────────────────────────────────┐
│  Focused                            [+]  [⚙]    │
├──────────────────────────────────────┬──────────┤
│                                      │  Sidebar │
│         SwiftTerm (active           │  ─────── │
│         tmux session, full           │ ▣ web    │
│         terminal emulation)          │   ~/api  │
│                                      │   idle   │
│                                      │ ▣ db     │
│                                      │   ~/web  │
│                                      │   ⏳ 5s  │
│                                      │ ▣ agent3 │
│                                      │   ~/db   │
│                                      │   ✓ done │ ← sorted by recency
└──────────────────────────────────────┴──────────┘
```

- Toolbar: 44px height, `Background Primary` (#f7f5f1), title in Inter 14/500, toolbar buttons are pill-shaped (10px radius) per the design system.
- Sidebar: 240px default width, user-resizable 200–400px. Background `Background Surface` (#faf8f4), `Border Default` (#e4ded4) divider on the left.
- Sidebar row: 64px tall, rounded 10px on hover/selected. Selected = `Accent Primary Light` (#e8dff5) background, 2px left border `Accent Primary` (#8B5CF6). Idle-bubble = 600ms green flash via `Success Background` (#f2f7ef).
- Status indicators: working = animated orange dot (#FF7A1A), idle = purple dot, done = green check (#34D399), exited = gray dot.
- Each row shows: short name, working directory (last path segment, secondary text), 2–3 lines of tail output (caption size, muted).
- `+` button: primary button style, `Accent Primary` background.
- `⚙` button: ghost style, opens settings sheet.

## Interactions

**Spawning**
- `+` toolbar button → NSOpenPanel (directories only) → new tmux session → `claude` launched → new session auto-selected.
- Secondary menu: a small chevron next to `+` opens a menu with "Shell" (runs `$SHELL` instead of `claude`) and "Custom command…" (prompts for a command string, stored only for that session).

**Switching**
- Click any sidebar row → AttachController switches to that session.
- 80ms crossfade between terminal views.
- Pre-switch soft-detach prevents leftover escape codes in the new view.

**Notifications**
- Requested on first spawn via `UNUserNotificationCenter.requestAuthorization`.
- On working→idle: title `"<name> is done"`, body shows working directory and the last non-empty line of pane content.
- Sound: default macOS notification sound, toggleable in settings.
- Click notification → app activates (`NSApp.activate(ignoringOtherApps: true)`) and selects that session.

**Sidebar ordering**
- Idle takes precedence over activity: a newly-idle session always bubbles to position 0.
- Among non-idle sessions, most-recently-active first.
- Idle-bubble: a newly-idle session moves to position 0; a 600ms green flash plays on its row.
- Queue: if a second session goes idle while the first is still flashing, the second is staged; when the flash ends, the second plays its own flash and takes position 0 (the first settles into position 1).
- Pinned sessions: right-click → "Pin" → pinned sessions keep their relative position regardless of activity. Pinned indicator = small purple dot prefix.

**Closing sessions**
- Hover sidebar row → `×` button appears.
- Click → `kill-session` via control mode.
- Confirmation prompt only if the pane has output in the last 60s (to avoid losing recent work); otherwise immediate.
- Claude Code's own `/exit` behaves identically (returns to shell, which is treated as `exited`).

**Keyboard shortcuts**
- `Cmd+T` — spawn new agent (focuses directory picker).
- `Cmd+1`..`Cmd+9` — switch to nth sidebar row.
- `Cmd+K` — kill current attach child (equivalent to quitting the visible session).
- `Cmd+,` — open settings.
- `Cmd+W` — close window (does not kill sessions).
- `Cmd+Q` — quit app (does not kill sessions).

**Settings sheet** (Cmd+,, or `⚙`)
- Notifications enabled (toggle, default on)
- Idle threshold (slider 0.5–5.0s, default 1.5s)
- Default agent command (text field, default `claude`)
- Theme: Auto / Light / Dark (default Auto; affects chrome only; terminal follows system)

## Error Handling

| Failure | Behavior |
|---|---|
| `tmux` not installed | First-launch check (`which tmux`). If missing, show full-window empty state with install command (`brew install tmux`) and a "Copy install command" button. Disable `+`. |
| `claude` not installed | Spawning still works (the shell starts). Sidebar row shows a small banner: "claude not found on PATH". The terminal itself shows the shell's "command not found" output. |
| Tmux server dies | Control-mode pipe breaks. App shows empty sidebar + sticky banner "tmux disconnected" + "Restart tmux" button. Click kills any stale server, runs `tmux -L focused start-server`, reconnects control mode. |
| Attach fails (session just died) | Catch the error, refresh session list, show a transient toast "That session ended". Sidebar removes the dead session. |
| Notification permission denied | Notifications silently off. Show a one-time banner "Enable notifications in System Settings to get done alerts" with "Open Settings" button. |
| Claude Code crashes mid-task | Pane shows shell prompt. Idle-detector sees shell (not `❯`), so session is marked `exited` (gray icon) with a toast on transition. Sidebar preview shows the last 2–3 lines (often a stack trace). |
| Sidebar overflow (>20 sessions) | Sidebar becomes scrollable. No virtualization in v1 (acceptable up to ~50 sessions; we can add lazy row rendering if profiling shows pain). |

## Testing Strategy

| Layer | Approach |
|---|---|
| `DoneDetector` | Unit tests against a recorded fixture of 20+ pane snapshots covering: idle prompt, mid-spinner, post-tool-call, exited shell, error trace, wrapped lines, empty pane. Pure function. |
| `SidebarStore` | State-machine tests: pin/unpin, idle-bubble, queue two finishes within flash window, selection preservation across reorder. |
| `TmuxControlClient` | Integration test using a real `tmux -L test` server in a temp dir, a fake agent script that prints predictable output, and assertions on `listSessions` / `capturePane` / `sendKeys`. Skipped in CI without tmux. |
| `NotificationManager` | Mock `UNUserNotificationCenter`. Assert one notification per working→idle edge, zero on idle→idle. |
| `AttachController` | Spawn a real `tmux attach-session` against a test session, feed bytes in, assert they appear in stdout. |
| SwiftTerm bridge | Manual visual smoke test: resize, Ctrl-C, paste, ANSI colors. We don't unit-test the terminal layer itself. |
| `Settings` | Round-trip test: write all four keys to UserDefaults, read back. |

## Open Questions

None at draft time. The "lazy sidebar previews" question (200ms for active, 1s for inactive) was resolved with the user during brainstorming.

## Implementation Notes

- Minimum macOS: 14.0 (Sonoma) — gives us `@Observable`, modern SwiftUI, SwiftTerm compatibility.
- SwiftTerm dependency: Swift Package Manager, `migueldeicaza/SwiftTerm` at the latest stable tag.
- No app-side persistence: UserDefaults holds only the four settings keys. Sessions themselves are 100% in tmux.
- Bundle identifier: `com.tombale.focused` (placeholder; to confirm before first build).
- The app's chrome follows the Jack & Jill design system. The terminal contents are rendered by SwiftTerm using Terminal.app's default colors, so they look like a real macOS terminal, not a themed one.
